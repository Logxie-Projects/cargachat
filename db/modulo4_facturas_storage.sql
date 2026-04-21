-- ============================================================
-- Módulo 4 — Facturas + Storage (cumplidos + facturas)
--
-- Cambios:
--   1. Tabla `facturas` + RLS (Logxie + transportadora dueña)
--   2. 2 buckets Storage: `cumplidos` y `facturas`
--   3. RLS buckets: Logxie full, transportadora propia, cliente vía
--      RPC fn_cumplido_by_ref (futuro rastrear.html)
--   4. Funciones SQL:
--      - fn_marcar_salida_cargue(viaje_id)
--      - fn_marcar_llegada_descargue(viaje_id)
--      - fn_subir_cumplido(pedido_id, foto_url, comentario, exitoso, novedad)
--      - fn_crear_factura(viaje_id, numero, monto, fecha_emision, pdf_url)
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Tabla facturas
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS facturas (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  numero            text NOT NULL,                               -- número propio del transportador
  viaje_id          uuid NOT NULL REFERENCES viajes_consolidados(id) ON DELETE CASCADE,
  transportadora_id uuid REFERENCES transportadoras(id),
  monto             numeric NOT NULL,
  fecha_emision     date NOT NULL,
  fecha_pago        date,
  pdf_url           text,
  estado            text NOT NULL DEFAULT 'emitida'
                    CHECK (estado IN ('emitida','pagada','anulada')),
  nota              text,
  created_by        uuid REFERENCES auth.users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (transportadora_id, numero)
);

CREATE INDEX IF NOT EXISTS idx_facturas_viaje ON facturas(viaje_id);
CREATE INDEX IF NOT EXISTS idx_facturas_transp ON facturas(transportadora_id);
CREATE INDEX IF NOT EXISTS idx_facturas_estado ON facturas(estado);

CREATE OR REPLACE FUNCTION _facturas_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_facturas_updated_at ON facturas;
CREATE TRIGGER trg_facturas_updated_at BEFORE UPDATE ON facturas
  FOR EACH ROW EXECUTE FUNCTION _facturas_updated_at();

ALTER TABLE facturas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS facturas_staff_all ON facturas;
DROP POLICY IF EXISTS facturas_transp_own ON facturas;
DROP POLICY IF EXISTS facturas_service_all ON facturas;

-- Logxie staff ve/escribe todo
CREATE POLICY facturas_staff_all ON facturas
  FOR ALL TO authenticated
  USING (is_logxie_staff())
  WITH CHECK (is_logxie_staff());

-- Transportadoras ven/escriben solo las suyas (futuro: validar perfil)
CREATE POLICY facturas_transp_own ON facturas
  FOR ALL TO authenticated
  USING (
    transportadora_id IN (
      SELECT id FROM transportadoras WHERE nombre = (
        SELECT empresa FROM perfiles WHERE id = auth.uid()
      )
    )
  )
  WITH CHECK (
    transportadora_id IN (
      SELECT id FROM transportadoras WHERE nombre = (
        SELECT empresa FROM perfiles WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY facturas_service_all ON facturas
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ------------------------------------------------------------
-- 2. Extender CHECK acciones_operador
-- ------------------------------------------------------------
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.acciones_operador'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%accion%'
  LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_accion_check
  CHECK (accion IN (
    'consolidar','agregar_pedido','quitar_pedido','desconsolidar',
    'ajustar_precio','publicar','invitar','asignar_directo',
    'adjudicar','cancelar','reasignar','reabrir',
    'sync_viajes','sync_pedidos','sync_seguimiento',
    'revisar_pedido','desmarcar_revision',
    'cerrar','cerrar_batch','reabrir_cierre',
    'cancelar_pedidos_batch','resetear_pedidos_batch','clonar_pedido',
    'editar_pedido','cambiar_estado_pedido','eliminar_pedido',
    'run_linkers',
    'asociar_viaje','desasociar_viaje',
    'cleanup_ghosts',
    'reintentar_entrega',
    'marcar_salida_cargue','marcar_llegada_cargue',
    'marcar_llegada_descargue','marcar_salida_descargue',
    'subir_cumplido','crear_factura','marcar_factura_pagada'
  ));

-- ------------------------------------------------------------
-- 3. Funciones de tracking (transportadora marca estado del viaje)
-- ------------------------------------------------------------
-- Helper: validar que el caller es la transportadora dueña del viaje
CREATE OR REPLACE FUNCTION _es_transportadora_del_viaje(p_viaje_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS(
    SELECT 1 FROM viajes_consolidados v
    LEFT JOIN perfiles p ON p.id = auth.uid()
    WHERE v.id = p_viaje_id
      AND (
        is_logxie_staff()
        OR (p.tipo = 'transportador' AND p.estado = 'aprobado'
            AND upper(trim(v.proveedor)) = upper(trim(p.empresa)))
      )
  );
$$;

CREATE OR REPLACE FUNCTION fn_marcar_llegada_cargue(p_viaje_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT _es_transportadora_del_viaje(p_viaje_id) THEN
    RAISE EXCEPTION 'No autorizado: solo Logxie staff o la transportadora del viaje';
  END IF;
  UPDATE viajes_consolidados SET llegada_cargue = COALESCE(llegada_cargue, now())
    WHERE id = p_viaje_id;
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'marcar_llegada_cargue', 'viaje', p_viaje_id, jsonb_build_object('ts', now()));
  RETURN jsonb_build_object('ok', true, 'llegada_cargue', now());
END;
$$;

CREATE OR REPLACE FUNCTION fn_marcar_salida_cargue(p_viaje_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT _es_transportadora_del_viaje(p_viaje_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  UPDATE viajes_consolidados SET salida_cargue = COALESCE(salida_cargue, now())
    WHERE id = p_viaje_id;
  -- Trigger recalc estado del viaje (set en_ruta automático via trigger existente)
  PERFORM fn_recalc_viaje_estado_desde_pedidos(p_viaje_id);
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'marcar_salida_cargue', 'viaje', p_viaje_id, jsonb_build_object('ts', now()));
  RETURN jsonb_build_object('ok', true, 'salida_cargue', now());
END;
$$;

CREATE OR REPLACE FUNCTION fn_marcar_llegada_descargue(p_viaje_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT _es_transportadora_del_viaje(p_viaje_id) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  UPDATE viajes_consolidados SET llegada_descargue = COALESCE(llegada_descargue, now())
    WHERE id = p_viaje_id;
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'marcar_llegada_descargue', 'viaje', p_viaje_id, jsonb_build_object('ts', now()));
  RETURN jsonb_build_object('ok', true, 'llegada_descargue', now());
END;
$$;

CREATE OR REPLACE FUNCTION fn_marcar_salida_descargue(p_viaje_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT _es_transportadora_del_viaje(p_viaje_id) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  UPDATE viajes_consolidados SET salida_descargue = COALESCE(salida_descargue, now())
    WHERE id = p_viaje_id;
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'marcar_salida_descargue', 'viaje', p_viaje_id, jsonb_build_object('ts', now()));
  RETURN jsonb_build_object('ok', true, 'salida_descargue', now());
END;
$$;

-- ------------------------------------------------------------
-- 4. fn_subir_cumplido(pedido_id, foto_url, comentario, exitoso, novedad)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_subir_cumplido(
  p_pedido_id  uuid,
  p_foto_url   text,
  p_comentario text DEFAULT NULL,
  p_exitoso    boolean DEFAULT true,
  p_novedad    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_viaje_id   uuid;
  v_next_num   int;
BEGIN
  SELECT viaje_id INTO v_viaje_id FROM pedidos WHERE id = p_pedido_id;
  IF v_viaje_id IS NULL THEN RAISE EXCEPTION 'Pedido sin viaje asociado'; END IF;

  IF NOT _es_transportadora_del_viaje(v_viaje_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  -- Calcular siguiente intento_num disponible
  SELECT COALESCE(MAX(intento_num), 0) + 1 INTO v_next_num
    FROM intentos_entrega WHERE pedido_id = p_pedido_id;
  IF v_next_num > 3 THEN RAISE EXCEPTION 'Ya hay 3 intentos; use fn_pedido_reintentar_entrega primero'; END IF;

  INSERT INTO intentos_entrega (
    pedido_id, intento_num, fecha, exitoso,
    novedad, comentario, foto_url, fuente, reportado_por
  ) VALUES (
    p_pedido_id, v_next_num, now(), p_exitoso,
    p_novedad, p_comentario, p_foto_url, 'app_conductor', auth.uid()
  );

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'subir_cumplido', 'pedido', p_pedido_id,
    jsonb_build_object('intento_num', v_next_num, 'exitoso', p_exitoso, 'foto_url', p_foto_url));

  RETURN jsonb_build_object('ok', true, 'intento_num', v_next_num);
END;
$$;

-- ------------------------------------------------------------
-- 5. fn_crear_factura
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_crear_factura(
  p_viaje_id      uuid,
  p_numero        text,
  p_monto         numeric,
  p_fecha_emision date,
  p_pdf_url       text DEFAULT NULL,
  p_nota          text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_transp_id uuid;
  v_factura_id uuid;
BEGIN
  IF NOT _es_transportadora_del_viaje(p_viaje_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  -- Resolver transportadora_id desde el viaje (si está seteada)
  SELECT transportadora_id INTO v_transp_id
    FROM viajes_consolidados WHERE id = p_viaje_id;

  -- Si transportadora_id es null, derivar via perfiles del caller
  IF v_transp_id IS NULL THEN
    SELECT t.id INTO v_transp_id FROM transportadoras t
      JOIN perfiles p ON upper(trim(t.nombre)) = upper(trim(p.empresa))
      WHERE p.id = auth.uid() LIMIT 1;
  END IF;

  INSERT INTO facturas (
    numero, viaje_id, transportadora_id, monto, fecha_emision,
    pdf_url, nota, created_by
  ) VALUES (
    p_numero, p_viaje_id, v_transp_id, p_monto, p_fecha_emision,
    p_pdf_url, p_nota, auth.uid()
  ) RETURNING id INTO v_factura_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'crear_factura', 'viaje', p_viaje_id,
    jsonb_build_object('factura_id', v_factura_id, 'numero', p_numero, 'monto', p_monto));

  RETURN jsonb_build_object('ok', true, 'factura_id', v_factura_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_marcar_llegada_cargue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_marcar_salida_cargue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_marcar_llegada_descargue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_marcar_salida_descargue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_subir_cumplido(uuid, text, text, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_crear_factura(uuid, text, numeric, date, text, text) TO authenticated;

COMMIT;

-- ============================================================
-- PASO 2 — Crear buckets Storage (requiere permisos storage.buckets)
-- ============================================================
-- Correr desde Supabase SQL Editor (necesita privilegios storage):
--
-- INSERT INTO storage.buckets (id, name, public) VALUES
--   ('cumplidos', 'cumplidos', true),
--   ('facturas',  'facturas',  false)
-- ON CONFLICT DO NOTHING;
--
-- (Público = cualquiera con URL puede ver. Facturas privado requiere signed URLs.)
--
-- Policies (Supabase Dashboard → Storage → Policies):
--
-- Bucket cumplidos:
--   SELECT: public (cualquier lector)
--   INSERT: authenticated (Logxie staff + transportadoras)
--   UPDATE/DELETE: Logxie staff solamente
--
-- Bucket facturas:
--   SELECT: authenticated AND (is_logxie_staff() OR ... owner check ...)
--   INSERT: authenticated
--   UPDATE/DELETE: Logxie staff
--
-- (Las policies de storage se crean desde el Dashboard con UI visual)
-- ============================================================

-- ============================================================
-- Módulo 4 — Tracking de intentos de entrega
--
-- Reemplaza parcialmente el Sheet "Seguimiento y Cumplidos".
-- Cada pedido puede tener hasta 3 intentos de entrega.
-- Regla de negocio: después de 3 intentos fallidos → 'devuelto_bodega'.
-- Regla de éxito: cualquier intento exitoso → 'entregado'.
--
-- Cambios:
--   1. pedidos.estado CHECK extendido con 'devuelto_bodega'
--   2. Tabla intentos_entrega + RLS
--   3. Trigger _recalc_pedido_estado_por_intentos (auto-transición)
--   4. fn_sync_pedidos_seguimiento_batch (desde CSV del Sheet)
--   5. acciones_operador CHECK extendido con 'sync_seguimiento'
--
-- Idempotente.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Extender CHECK pedidos.estado
-- ------------------------------------------------------------
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.pedidos'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%estado%'
  LOOP
    EXECUTE format('ALTER TABLE pedidos DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE pedidos ADD CONSTRAINT pedidos_estado_check
  CHECK (estado IN (
    'sin_consolidar','por_revisar','consolidado','asignado',
    'en_ruta','entregado','entregado_novedad','rechazado',
    'cancelado','devuelto_bodega'
  ));

-- ------------------------------------------------------------
-- 2. Tabla intentos_entrega
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intentos_entrega (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id     uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  intento_num   int NOT NULL CHECK (intento_num BETWEEN 1 AND 3),
  fecha         timestamptz,
  exitoso       boolean NOT NULL DEFAULT false,
  novedad       text,
  comentario    text,
  foto_url      text,
  fuente        text NOT NULL DEFAULT 'sheet'
                    CHECK (fuente IN ('sheet','netfleet','app_conductor')),
  reportado_por uuid REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pedido_id, intento_num)
);

CREATE INDEX IF NOT EXISTS idx_intentos_pedido ON intentos_entrega(pedido_id);
CREATE INDEX IF NOT EXISTS idx_intentos_fecha  ON intentos_entrega(fecha DESC);

-- Trigger updated_at
CREATE OR REPLACE FUNCTION _intentos_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_intentos_updated_at ON intentos_entrega;
CREATE TRIGGER trg_intentos_updated_at BEFORE UPDATE ON intentos_entrega
  FOR EACH ROW EXECUTE FUNCTION _intentos_updated_at();

-- RLS
ALTER TABLE intentos_entrega ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS intentos_staff_all ON intentos_entrega;
DROP POLICY IF EXISTS intentos_service_all ON intentos_entrega;

CREATE POLICY intentos_staff_all ON intentos_entrega
  FOR ALL TO authenticated
  USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());

CREATE POLICY intentos_service_all ON intentos_entrega
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ------------------------------------------------------------
-- 3. Trigger: recalcular estado del pedido al insertar/modificar intento
--    Regla:
--      - Cualquier intento exitoso → pedido.estado = 'entregado' (o 'entregado_novedad' si novedad)
--      - 3 intentos, todos fallidos → pedido.estado = 'devuelto_bodega'
--      - Sino → no tocar (queda en_ruta u otro)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _recalc_pedido_estado_por_intentos()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_intentos       int;
  v_exitosos       int;
  v_exitoso_con_nov boolean;
  v_max_num        int;
  v_target_estado  text;
BEGIN
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE exitoso),
         bool_or(exitoso AND novedad IS NOT NULL AND trim(novedad) <> ''),
         max(intento_num)
    INTO v_intentos, v_exitosos, v_exitoso_con_nov, v_max_num
    FROM intentos_entrega
    WHERE pedido_id = NEW.pedido_id;

  IF v_exitosos > 0 THEN
    v_target_estado := CASE WHEN v_exitoso_con_nov THEN 'entregado_novedad' ELSE 'entregado' END;
  ELSIF v_max_num >= 3 AND v_exitosos = 0 THEN
    v_target_estado := 'devuelto_bodega';
  ELSE
    v_target_estado := NULL;  -- no tocar
  END IF;

  IF v_target_estado IS NOT NULL THEN
    UPDATE pedidos SET estado = v_target_estado
      WHERE id = NEW.pedido_id AND estado IS DISTINCT FROM v_target_estado;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_intentos_recalc_estado ON intentos_entrega;
CREATE TRIGGER trg_intentos_recalc_estado
  AFTER INSERT OR UPDATE ON intentos_entrega
  FOR EACH ROW EXECUTE FUNCTION _recalc_pedido_estado_por_intentos();

-- ------------------------------------------------------------
-- 4. Extender CHECK acciones_operador con 'sync_seguimiento'
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
    'reintentar_entrega'
  ));

-- ------------------------------------------------------------
-- 5. fn_sync_pedidos_seguimiento_batch
--    Input JSON array, cada objeto con:
--      id_inicio, seguimiento_estado,
--      intento_1_fecha, intento_1_comentario, intento_1_novedad,
--      intento_2_fecha, intento_2_comentario,
--      intento_3_fecha, intento_3_comentario,
--      foto_cumplido
--
--    Lógica del exitoso:
--      - ESTADO del sheet ∈ ('Entregado OK','Entregado con Novedad') → ultimo intento fue exitoso
--      - Otros valores → todos los intentos son fallidos (o aún pendiente)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sync_pedidos_seguimiento_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row        jsonb;
  v_id_inicio  text;
  v_pedido_id  uuid;
  v_seg_est    text;
  v_exitoso    boolean;
  v_num        int;
  v_fecha      timestamptz;
  v_coment     text;
  v_novedad    text;
  v_foto       text;
  v_max_ok     int;

  c_intentos_ins  int := 0;
  c_intentos_upd  int := 0;
  c_pedidos_touch int := 0;
  c_no_match      int := 0;
  c_errores       int := 0;
  err_samples     jsonb := '[]'::jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede disparar sync seguimiento';
  END IF;

  IF jsonb_typeof(p_payload) <> 'array' THEN
    RAISE EXCEPTION 'payload debe ser un array JSON';
  END IF;

  FOR v_row IN SELECT jsonb_array_elements(p_payload) LOOP
    BEGIN
      v_id_inicio := NULLIF(trim(v_row->>'id_inicio'), '');
      IF v_id_inicio IS NULL THEN CONTINUE; END IF;

      SELECT id INTO v_pedido_id FROM pedidos WHERE id_inicio = v_id_inicio LIMIT 1;
      IF v_pedido_id IS NULL THEN
        c_no_match := c_no_match + 1;
        CONTINUE;
      END IF;

      v_seg_est := upper(trim(coalesce(v_row->>'seguimiento_estado', '')));
      v_foto    := NULLIF(trim(coalesce(v_row->>'foto_cumplido', '')), '');

      -- Determinar cuál intento es el exitoso (si hay alguno)
      v_exitoso := v_seg_est IN ('ENTREGADO OK','ENTREGADO CON NOVEDAD');

      -- Propagación directa del estado desde Sheet (independiente de si hay timestamps de intento)
      -- Muchas filas tienen ESTADO="Entregado OK" sin timestamp → igual actualiza el pedido.
      IF v_seg_est = 'ENTREGADO OK' THEN
        UPDATE pedidos SET estado = 'entregado'
          WHERE id = v_pedido_id AND estado <> 'entregado';
        c_pedidos_touch := c_pedidos_touch + 1;
      ELSIF v_seg_est = 'ENTREGADO CON NOVEDAD' THEN
        UPDATE pedidos SET estado = 'entregado_novedad'
          WHERE id = v_pedido_id AND estado <> 'entregado_novedad';
        c_pedidos_touch := c_pedidos_touch + 1;
      ELSIF v_seg_est = 'RECHAZADO POR CLIENTE' THEN
        UPDATE pedidos SET estado = 'rechazado'
          WHERE id = v_pedido_id
            AND estado NOT IN ('entregado','entregado_novedad','devuelto_bodega','cancelado');
      ELSIF v_seg_est = 'PENDIENTE' THEN
        UPDATE pedidos SET estado = 'en_ruta'
          WHERE id = v_pedido_id AND estado IN ('consolidado','asignado');
      END IF;

      -- Encontrar el max intento_num CON DATOS (fecha O comentario O (num=1 Y (foto O novedad)))
      v_max_ok := 0;
      FOR v_num IN 1..3 LOOP
        IF NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_fecha'), '')), '') IS NOT NULL
           OR NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_comentario'), '')), '') IS NOT NULL
           OR (v_num = 1 AND (v_foto IS NOT NULL
               OR NULLIF(trim(coalesce(v_row->>'intento_1_novedad', '')), '') IS NOT NULL))
        THEN v_max_ok := v_num;
        END IF;
      END LOOP;

      -- Si el estado es terminal (entregado/rechazado) pero no hay ningún dato de intento,
      -- crear igual un intento 1 sintético (para registrar el evento sin fecha).
      IF v_max_ok = 0 AND v_seg_est IN ('ENTREGADO OK','ENTREGADO CON NOVEDAD','RECHAZADO POR CLIENTE')
      THEN v_max_ok := 1; END IF;

      IF v_max_ok = 0 THEN CONTINUE; END IF;

      -- Upsert cada intento (fecha puede ser NULL — Sheet a veces no tiene timestamp)
      FOR v_num IN 1..v_max_ok LOOP
        v_fecha  := NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_fecha'), '')), '')::timestamptz;
        v_coment := NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_comentario'), '')), '');
        v_novedad := CASE
          WHEN v_num = 1 THEN NULLIF(trim(coalesce(v_row->>'intento_1_novedad', '')), '')
          ELSE NULL
        END;

        INSERT INTO intentos_entrega (
          pedido_id, intento_num, fecha, exitoso,
          novedad, comentario, foto_url, fuente
        ) VALUES (
          v_pedido_id, v_num, v_fecha,
          (v_num = v_max_ok AND v_exitoso),
          v_novedad, v_coment,
          CASE WHEN v_num = v_max_ok THEN v_foto ELSE NULL END,
          'sheet'
        )
        ON CONFLICT (pedido_id, intento_num) DO UPDATE
        SET fecha       = COALESCE(EXCLUDED.fecha,      intentos_entrega.fecha),
            exitoso     = EXCLUDED.exitoso,
            novedad     = COALESCE(EXCLUDED.novedad,    intentos_entrega.novedad),
            comentario  = COALESCE(EXCLUDED.comentario, intentos_entrega.comentario),
            foto_url    = COALESCE(EXCLUDED.foto_url,   intentos_entrega.foto_url),
            updated_at  = now();

        IF FOUND THEN c_intentos_ins := c_intentos_ins + 1; END IF;
      END LOOP;

      c_pedidos_touch := c_pedidos_touch + 1;
    EXCEPTION WHEN others THEN
      c_errores := c_errores + 1;
      IF jsonb_array_length(err_samples) < 5 THEN
        err_samples := err_samples || jsonb_build_object(
          'id_inicio', v_id_inicio, 'error', SQLERRM
        );
      END IF;
    END;
  END LOOP;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'sync_seguimiento', 'pedido',
    '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'intentos_touched', c_intentos_ins,
      'pedidos_touched',  c_pedidos_touch,
      'no_match',         c_no_match,
      'errores',          c_errores,
      'err_samples',      err_samples,
      'total_input',      jsonb_array_length(p_payload)
    ));

  RETURN jsonb_build_object(
    'intentos_touched', c_intentos_ins,
    'pedidos_touched',  c_pedidos_touch,
    'no_match',         c_no_match,
    'errores',          c_errores,
    'err_samples',      err_samples,
    'total_input',      jsonb_array_length(p_payload)
  );
END;
$$;

-- ------------------------------------------------------------
-- 6. fn_pedido_reintentar_entrega
--    Si devuelto_bodega → limpia intentos y resetea estado a 'asignado'
--    para que pueda reintentar (hasta 3 intentos nuevos).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_pedido_reintentar_entrega(
  p_pedido_id uuid,
  p_razon     text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
  v_borrados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role') THEN
    RAISE EXCEPTION 'Solo logxie_staff';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida';
  END IF;

  SELECT estado INTO v_estado FROM pedidos WHERE id = p_pedido_id;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'Pedido no existe'; END IF;

  DELETE FROM intentos_entrega WHERE pedido_id = p_pedido_id;
  GET DIAGNOSTICS v_borrados = ROW_COUNT;

  UPDATE pedidos SET estado = 'asignado' WHERE id = p_pedido_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'reintentar_entrega', 'pedido', p_pedido_id,
    jsonb_build_object(
      'estado_anterior', v_estado,
      'intentos_borrados', v_borrados,
      'razon', p_razon
    ));

  RETURN jsonb_build_object('intentos_borrados', v_borrados);
END;
$$;

COMMIT;

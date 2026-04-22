-- ============================================================
-- Módulo 4 — Flota (conductores + vehículos + documentos_flota)
--
-- Cambios:
--   1. ALTER perfiles ADD transportadora_id FK (link explícito usuario↔transportadora)
--   2. Tablas conductores + vehiculos + documentos_flota (polimórfico)
--   3. Bucket Storage 'flota-docs' privado + policies
--   4. 6 functions: fn_flota_conductor_upsert/desactivar,
--      fn_flota_vehiculo_upsert/desactivar, fn_flota_doc_upsert/eliminar
--   5. Helper _mi_transportadora_id() con fallback string-match
--   6. Extender acciones_operador CHECK (accion + entidad_tipo)
--   7. Link test user bernardojaristizabal@gmail.com → JR LOGÍSTICA
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. perfiles.transportadora_id (FK explícito)
-- ------------------------------------------------------------
ALTER TABLE perfiles
  ADD COLUMN IF NOT EXISTS transportadora_id UUID REFERENCES transportadoras(id);
CREATE INDEX IF NOT EXISTS idx_perfiles_transp ON perfiles(transportadora_id);

-- ------------------------------------------------------------
-- 2. Tabla conductores
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conductores (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transportadora_id    UUID NOT NULL REFERENCES transportadoras(id) ON DELETE CASCADE,
  nombre               TEXT NOT NULL,
  cedula               TEXT,
  licencia_numero      TEXT,
  licencia_categoria   TEXT,                     -- 'B1','C1','C2','C3',...
  telefono             TEXT,
  email                TEXT,
  activo               BOOLEAN NOT NULL DEFAULT true,
  notas                TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by           UUID REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_conductores_transp ON conductores(transportadora_id) WHERE activo;
CREATE UNIQUE INDEX IF NOT EXISTS idx_conductores_cedula_transp
  ON conductores(transportadora_id, cedula) WHERE cedula IS NOT NULL;

-- ------------------------------------------------------------
-- 3. Tabla vehiculos
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehiculos (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transportadora_id    UUID NOT NULL REFERENCES transportadoras(id) ON DELETE CASCADE,
  placa                TEXT NOT NULL,
  tipo                 TEXT,                     -- 'Turbo','Sencillo','Mini-mula','Tractomula',...
  marca                TEXT,
  modelo_anio          INT,
  capacidad_kg         NUMERIC,
  configuracion_ejes   TEXT,                     -- '2 ejes','3 ejes','6x4',...
  activo               BOOLEAN NOT NULL DEFAULT true,
  notas                TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by           UUID REFERENCES auth.users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_vehiculos_placa_transp
  ON vehiculos(transportadora_id, placa);
CREATE INDEX IF NOT EXISTS idx_vehiculos_transp ON vehiculos(transportadora_id) WHERE activo;

-- ------------------------------------------------------------
-- 4. Tabla documentos_flota (polimórfico)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documentos_flota (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transportadora_id  UUID NOT NULL REFERENCES transportadoras(id) ON DELETE CASCADE,
  entidad_tipo       TEXT NOT NULL CHECK (entidad_tipo IN ('conductor','vehiculo')),
  entidad_id         UUID NOT NULL,
  tipo_doc           TEXT NOT NULL,    -- 'cedula','licencia','eps','arl','sust_peligrosas',
                                       -- 'examen_medico','hoja_vida','tarjeta_propiedad',
                                       -- 'soat','tecnomecanica','poliza_rc','foto_vehiculo'
  archivo_url        TEXT,             -- path en bucket flota-docs
  vence_at           DATE,             -- NULL si no aplica (cédula, tarjeta propiedad)
  subido_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  subido_por         UUID REFERENCES auth.users(id),
  notas              TEXT,
  UNIQUE (entidad_tipo, entidad_id, tipo_doc)
);
CREATE INDEX IF NOT EXISTS idx_docs_flota_entidad ON documentos_flota(entidad_tipo, entidad_id);
CREATE INDEX IF NOT EXISTS idx_docs_flota_transp ON documentos_flota(transportadora_id);
CREATE INDEX IF NOT EXISTS idx_docs_flota_vence ON documentos_flota(vence_at) WHERE vence_at IS NOT NULL;

-- ------------------------------------------------------------
-- 5. Triggers updated_at
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _flota_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_conductores_updated_at ON conductores;
CREATE TRIGGER trg_conductores_updated_at BEFORE UPDATE ON conductores
  FOR EACH ROW EXECUTE FUNCTION _flota_updated_at();

DROP TRIGGER IF EXISTS trg_vehiculos_updated_at ON vehiculos;
CREATE TRIGGER trg_vehiculos_updated_at BEFORE UPDATE ON vehiculos
  FOR EACH ROW EXECUTE FUNCTION _flota_updated_at();

-- ------------------------------------------------------------
-- 6. Helper: transportadora del usuario autenticado
--    Prioridad 1: perfiles.transportadora_id (FK explícito)
--    Prioridad 2: fallback string-match perfiles.empresa ↔ transportadoras.nombre
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _mi_transportadora_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT transportadora_id FROM perfiles WHERE id = auth.uid()),
    (SELECT t.id FROM perfiles p
      JOIN transportadoras t
        ON upper(trim(p.empresa)) LIKE '%' || upper(trim(t.nombre)) || '%'
      WHERE p.id = auth.uid()
      LIMIT 1)
  );
$$;
GRANT EXECUTE ON FUNCTION _mi_transportadora_id() TO authenticated;

-- ------------------------------------------------------------
-- 7. RLS
-- ------------------------------------------------------------
ALTER TABLE conductores        ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehiculos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos_flota   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conductores_staff_all      ON conductores;
DROP POLICY IF EXISTS conductores_transp_own     ON conductores;
DROP POLICY IF EXISTS conductores_service_all    ON conductores;
DROP POLICY IF EXISTS vehiculos_staff_all        ON vehiculos;
DROP POLICY IF EXISTS vehiculos_transp_own       ON vehiculos;
DROP POLICY IF EXISTS vehiculos_service_all      ON vehiculos;
DROP POLICY IF EXISTS docs_flota_staff_all       ON documentos_flota;
DROP POLICY IF EXISTS docs_flota_transp_own      ON documentos_flota;
DROP POLICY IF EXISTS docs_flota_service_all     ON documentos_flota;

-- Logxie staff: todo
CREATE POLICY conductores_staff_all ON conductores FOR ALL TO authenticated
  USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());
CREATE POLICY vehiculos_staff_all ON vehiculos FOR ALL TO authenticated
  USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());
CREATE POLICY docs_flota_staff_all ON documentos_flota FOR ALL TO authenticated
  USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());

-- Transportadora: solo la suya
CREATE POLICY conductores_transp_own ON conductores FOR ALL TO authenticated
  USING (transportadora_id = _mi_transportadora_id())
  WITH CHECK (transportadora_id = _mi_transportadora_id());
CREATE POLICY vehiculos_transp_own ON vehiculos FOR ALL TO authenticated
  USING (transportadora_id = _mi_transportadora_id())
  WITH CHECK (transportadora_id = _mi_transportadora_id());
CREATE POLICY docs_flota_transp_own ON documentos_flota FOR ALL TO authenticated
  USING (transportadora_id = _mi_transportadora_id())
  WITH CHECK (transportadora_id = _mi_transportadora_id());

-- service_role: todo
CREATE POLICY conductores_service_all ON conductores FOR ALL TO service_role
  USING (true) WITH CHECK (true);
CREATE POLICY vehiculos_service_all ON vehiculos FOR ALL TO service_role
  USING (true) WITH CHECK (true);
CREATE POLICY docs_flota_service_all ON documentos_flota FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ------------------------------------------------------------
-- 8. Extender acciones_operador CHECK (accion + entidad_tipo)
-- ------------------------------------------------------------
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid='public.acciones_operador'::regclass AND contype='c'
      AND pg_get_constraintdef(oid) ILIKE '%accion%' LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_accion_check CHECK (accion IN (
    'consolidar','agregar_pedido','quitar_pedido','desconsolidar',
    'ajustar_precio','publicar','invitar','asignar_directo',
    'adjudicar','cancelar','reasignar','reabrir',
    'sync_viajes','sync_pedidos','sync_seguimiento',
    'run_linkers','cleanup_ghosts',
    'revisar_pedido','desmarcar_revision',
    'cerrar','cerrar_batch','reabrir_cierre',
    'cancelar_pedidos_batch','resetear_pedidos_batch','clonar_pedido',
    'editar_pedido','cambiar_estado_pedido','eliminar_pedido',
    'asociar_viaje','desasociar_viaje','reintentar_entrega',
    'marcar_salida_cargue','marcar_llegada_cargue',
    'marcar_llegada_descargue','marcar_salida_descargue',
    'subir_cumplido','crear_factura','marcar_factura_pagada',
    'scenario_crear','scenario_agregar_pedido','scenario_quitar_pedido',
    'scenario_descartar','scenario_promover','scenario_limpiar',
    'flota_conductor_crear','flota_conductor_editar','flota_conductor_desactivar',
    'flota_vehiculo_crear','flota_vehiculo_editar','flota_vehiculo_desactivar',
    'flota_doc_subir','flota_doc_eliminar'
  ));

DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid='public.acciones_operador'::regclass AND contype='c'
      AND pg_get_constraintdef(oid) ILIKE '%entidad_tipo%' LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_entidad_tipo_check
  CHECK (entidad_tipo IN ('viaje','pedido','oferta','scenario','conductor','vehiculo','doc_flota'));

-- ------------------------------------------------------------
-- 9. Functions CRUD
-- ------------------------------------------------------------

-- fn_flota_conductor_upsert
CREATE OR REPLACE FUNCTION fn_flota_conductor_upsert(
  p_id                 UUID,
  p_nombre             TEXT,
  p_cedula             TEXT DEFAULT NULL,
  p_licencia_numero    TEXT DEFAULT NULL,
  p_licencia_categoria TEXT DEFAULT NULL,
  p_telefono           TEXT DEFAULT NULL,
  p_email              TEXT DEFAULT NULL,
  p_notas              TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_transp_id UUID;
  v_cond_id   UUID;
BEGIN
  v_transp_id := _mi_transportadora_id();
  IF v_transp_id IS NULL AND NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'No se encontró transportadora para el usuario';
  END IF;
  IF trim(coalesce(p_nombre,'')) = '' THEN
    RAISE EXCEPTION 'Nombre requerido';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO conductores (
      transportadora_id, nombre, cedula, licencia_numero, licencia_categoria,
      telefono, email, notas, created_by
    ) VALUES (
      v_transp_id, trim(p_nombre),
      NULLIF(trim(p_cedula),''), NULLIF(trim(p_licencia_numero),''),
      NULLIF(trim(p_licencia_categoria),''),
      NULLIF(trim(p_telefono),''), NULLIF(trim(p_email),''),
      NULLIF(trim(p_notas),''), auth.uid()
    ) RETURNING id INTO v_cond_id;

    INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'flota_conductor_crear', 'conductor', v_cond_id,
      jsonb_build_object('nombre', p_nombre, 'transportadora_id', v_transp_id));
  ELSE
    UPDATE conductores SET
      nombre             = trim(p_nombre),
      cedula             = NULLIF(trim(p_cedula),''),
      licencia_numero    = NULLIF(trim(p_licencia_numero),''),
      licencia_categoria = NULLIF(trim(p_licencia_categoria),''),
      telefono           = NULLIF(trim(p_telefono),''),
      email              = NULLIF(trim(p_email),''),
      notas              = NULLIF(trim(p_notas),'')
    WHERE id = p_id
      AND (transportadora_id = v_transp_id OR is_logxie_staff())
    RETURNING id INTO v_cond_id;
    IF v_cond_id IS NULL THEN RAISE EXCEPTION 'Conductor no existe o no autorizado'; END IF;
    INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'flota_conductor_editar', 'conductor', v_cond_id,
      jsonb_build_object('nombre', p_nombre));
  END IF;
  RETURN v_cond_id;
END;
$$;

-- fn_flota_conductor_desactivar (soft delete, toggle)
CREATE OR REPLACE FUNCTION fn_flota_conductor_desactivar(
  p_id     UUID,
  p_activo BOOLEAN DEFAULT false
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_transp_id UUID;
BEGIN
  v_transp_id := _mi_transportadora_id();
  UPDATE conductores SET activo = p_activo
    WHERE id = p_id
      AND (transportadora_id = v_transp_id OR is_logxie_staff());
  IF NOT FOUND THEN RAISE EXCEPTION 'No autorizado o conductor no existe'; END IF;
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'flota_conductor_desactivar', 'conductor', p_id,
    jsonb_build_object('activo', p_activo));
END;
$$;

-- fn_flota_vehiculo_upsert
CREATE OR REPLACE FUNCTION fn_flota_vehiculo_upsert(
  p_id                  UUID,
  p_placa               TEXT,
  p_tipo                TEXT DEFAULT NULL,
  p_marca               TEXT DEFAULT NULL,
  p_modelo_anio         INT  DEFAULT NULL,
  p_capacidad_kg        NUMERIC DEFAULT NULL,
  p_configuracion_ejes  TEXT DEFAULT NULL,
  p_notas               TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_transp_id UUID;
  v_veh_id    UUID;
BEGIN
  v_transp_id := _mi_transportadora_id();
  IF v_transp_id IS NULL AND NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'No se encontró transportadora para el usuario';
  END IF;
  IF trim(coalesce(p_placa,'')) = '' THEN
    RAISE EXCEPTION 'Placa requerida';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO vehiculos (
      transportadora_id, placa, tipo, marca, modelo_anio,
      capacidad_kg, configuracion_ejes, notas, created_by
    ) VALUES (
      v_transp_id, upper(trim(p_placa)),
      NULLIF(trim(p_tipo),''), NULLIF(trim(p_marca),''), p_modelo_anio,
      p_capacidad_kg, NULLIF(trim(p_configuracion_ejes),''),
      NULLIF(trim(p_notas),''), auth.uid()
    ) RETURNING id INTO v_veh_id;
    INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'flota_vehiculo_crear', 'vehiculo', v_veh_id,
      jsonb_build_object('placa', upper(trim(p_placa)), 'transportadora_id', v_transp_id));
  ELSE
    UPDATE vehiculos SET
      placa              = upper(trim(p_placa)),
      tipo               = NULLIF(trim(p_tipo),''),
      marca              = NULLIF(trim(p_marca),''),
      modelo_anio        = p_modelo_anio,
      capacidad_kg       = p_capacidad_kg,
      configuracion_ejes = NULLIF(trim(p_configuracion_ejes),''),
      notas              = NULLIF(trim(p_notas),'')
    WHERE id = p_id
      AND (transportadora_id = v_transp_id OR is_logxie_staff())
    RETURNING id INTO v_veh_id;
    IF v_veh_id IS NULL THEN RAISE EXCEPTION 'Vehículo no existe o no autorizado'; END IF;
    INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'flota_vehiculo_editar', 'vehiculo', v_veh_id,
      jsonb_build_object('placa', upper(trim(p_placa))));
  END IF;
  RETURN v_veh_id;
END;
$$;

-- fn_flota_vehiculo_desactivar
CREATE OR REPLACE FUNCTION fn_flota_vehiculo_desactivar(
  p_id     UUID,
  p_activo BOOLEAN DEFAULT false
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_transp_id UUID;
BEGIN
  v_transp_id := _mi_transportadora_id();
  UPDATE vehiculos SET activo = p_activo
    WHERE id = p_id
      AND (transportadora_id = v_transp_id OR is_logxie_staff());
  IF NOT FOUND THEN RAISE EXCEPTION 'No autorizado o vehículo no existe'; END IF;
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'flota_vehiculo_desactivar', 'vehiculo', p_id,
    jsonb_build_object('activo', p_activo));
END;
$$;

-- fn_flota_doc_upsert (upsert por tipo_doc dentro de entidad)
CREATE OR REPLACE FUNCTION fn_flota_doc_upsert(
  p_entidad_tipo TEXT,
  p_entidad_id   UUID,
  p_tipo_doc     TEXT,
  p_archivo_url  TEXT,
  p_vence_at     DATE DEFAULT NULL,
  p_notas        TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_transp_id       UUID;
  v_entidad_transp  UUID;
  v_doc_id          UUID;
BEGIN
  IF p_entidad_tipo NOT IN ('conductor','vehiculo') THEN
    RAISE EXCEPTION 'entidad_tipo inválido (conductor|vehiculo)';
  END IF;
  IF trim(coalesce(p_tipo_doc,'')) = '' THEN
    RAISE EXCEPTION 'tipo_doc requerido';
  END IF;

  IF p_entidad_tipo = 'conductor' THEN
    SELECT transportadora_id INTO v_entidad_transp FROM conductores WHERE id = p_entidad_id;
  ELSE
    SELECT transportadora_id INTO v_entidad_transp FROM vehiculos WHERE id = p_entidad_id;
  END IF;
  IF v_entidad_transp IS NULL THEN RAISE EXCEPTION 'Entidad no existe'; END IF;

  v_transp_id := _mi_transportadora_id();
  IF v_entidad_transp IS DISTINCT FROM v_transp_id AND NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  INSERT INTO documentos_flota (
    transportadora_id, entidad_tipo, entidad_id, tipo_doc,
    archivo_url, vence_at, subido_por, notas
  ) VALUES (
    v_entidad_transp, p_entidad_tipo, p_entidad_id, p_tipo_doc,
    p_archivo_url, p_vence_at, auth.uid(), NULLIF(trim(p_notas),'')
  )
  ON CONFLICT (entidad_tipo, entidad_id, tipo_doc) DO UPDATE SET
    archivo_url = EXCLUDED.archivo_url,
    vence_at    = EXCLUDED.vence_at,
    subido_at   = now(),
    subido_por  = auth.uid(),
    notas       = EXCLUDED.notas
  RETURNING id INTO v_doc_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'flota_doc_subir', 'doc_flota', v_doc_id,
    jsonb_build_object(
      'entidad_tipo', p_entidad_tipo, 'entidad_id', p_entidad_id,
      'tipo_doc', p_tipo_doc, 'vence_at', p_vence_at
    ));
  RETURN v_doc_id;
END;
$$;

-- fn_flota_doc_eliminar
CREATE OR REPLACE FUNCTION fn_flota_doc_eliminar(p_doc_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_transp_id UUID;
  v_url       TEXT;
BEGIN
  v_transp_id := _mi_transportadora_id();
  SELECT archivo_url INTO v_url FROM documentos_flota WHERE id = p_doc_id;
  DELETE FROM documentos_flota WHERE id = p_doc_id
    AND (transportadora_id = v_transp_id OR is_logxie_staff());
  IF NOT FOUND THEN RAISE EXCEPTION 'No autorizado o doc no existe'; END IF;
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'flota_doc_eliminar', 'doc_flota', p_doc_id,
    jsonb_build_object('archivo_url', v_url));
END;
$$;

GRANT EXECUTE ON FUNCTION fn_flota_conductor_upsert(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_flota_conductor_desactivar(UUID,BOOLEAN)             TO authenticated;
GRANT EXECUTE ON FUNCTION fn_flota_vehiculo_upsert(UUID,TEXT,TEXT,TEXT,INT,NUMERIC,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_flota_vehiculo_desactivar(UUID,BOOLEAN)              TO authenticated;
GRANT EXECUTE ON FUNCTION fn_flota_doc_upsert(TEXT,UUID,TEXT,TEXT,DATE,TEXT)      TO authenticated;
GRANT EXECUTE ON FUNCTION fn_flota_doc_eliminar(UUID)                              TO authenticated;

-- ------------------------------------------------------------
-- 10. Bucket Storage flota-docs (privado) + policies
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('flota-docs', 'flota-docs', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "flota_docs_staff_all"     ON storage.objects;
DROP POLICY IF EXISTS "flota_docs_transp_select" ON storage.objects;
DROP POLICY IF EXISTS "flota_docs_transp_insert" ON storage.objects;
DROP POLICY IF EXISTS "flota_docs_transp_update" ON storage.objects;
DROP POLICY IF EXISTS "flota_docs_transp_delete" ON storage.objects;

-- Staff: todo
CREATE POLICY "flota_docs_staff_all" ON storage.objects
  FOR ALL TO authenticated
  USING      (bucket_id = 'flota-docs' AND is_logxie_staff())
  WITH CHECK (bucket_id = 'flota-docs' AND is_logxie_staff());

-- Transportadora: solo la suya (path format: {transp_id}/{entidad_tipo}/{entidad_id}/...)
CREATE POLICY "flota_docs_transp_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'flota-docs'
    AND (storage.foldername(name))[1]::uuid = _mi_transportadora_id());

CREATE POLICY "flota_docs_transp_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'flota-docs'
    AND (storage.foldername(name))[1]::uuid = _mi_transportadora_id());

CREATE POLICY "flota_docs_transp_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'flota-docs'
    AND (storage.foldername(name))[1]::uuid = _mi_transportadora_id());

CREATE POLICY "flota_docs_transp_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'flota-docs'
    AND (storage.foldername(name))[1]::uuid = _mi_transportadora_id());

-- ------------------------------------------------------------
-- 11. Link test user bernardojaristizabal@gmail.com → JR LOGÍSTICA
-- ------------------------------------------------------------
UPDATE perfiles
  SET transportadora_id = '97c46fd6-18ae-44ec-ac3c-2a9e372f7659'
  WHERE id = 'e2269e48-34f2-45c6-9fca-a3cbd854347b'
    AND transportadora_id IS NULL;

COMMIT;

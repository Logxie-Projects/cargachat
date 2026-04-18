-- ============================================================
-- MÓDULO 4 — Schema extra (paso 2 de 3)
-- Tablas: transportadoras, ofertas, invitaciones_subasta
-- ALTERs: viajes_consolidados (+6 cols), acciones_operador.accion CHECK
--
-- Precondición: perfiles.sql + modulo4_schema.sql ya corridos.
-- Idempotente.
-- ============================================================

BEGIN;

-- ============================================================
-- 1) TRANSPORTADORAS
-- ============================================================
CREATE TABLE IF NOT EXISTS transportadoras (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          text NOT NULL UNIQUE,
  nit             text,
  email_contacto  text,
  telefono        text,
  whatsapp        text,
  zonas_operadas  text[],                -- ['ANTIOQUIA', 'LLANOS', ...]
  tipos_vehiculos text[],                -- ['Tractomula', 'NHR', 'Sencillo']
  activo          boolean NOT NULL DEFAULT true,
  notas           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transportadoras_activo ON transportadoras(activo);

DROP TRIGGER IF EXISTS transportadoras_updated_at ON transportadoras;
CREATE TRIGGER transportadoras_updated_at
  BEFORE UPDATE ON transportadoras
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE transportadoras ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_read" ON transportadoras;
CREATE POLICY "authenticated_read" ON transportadoras
  FOR SELECT TO authenticated USING (activo = true OR is_logxie_staff());

DROP POLICY IF EXISTS "staff_all" ON transportadoras;
CREATE POLICY "staff_all" ON transportadoras
  FOR ALL TO authenticated USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());

DROP POLICY IF EXISTS "service_role_all" ON transportadoras;
CREATE POLICY "service_role_all" ON transportadoras
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Seed con los proveedores conocidos (desde CLAUDE.md)
INSERT INTO transportadoras (nombre, email_contacto, notas)
VALUES
  ('ENTRAPETROL',            'gerencia@stentrapetrol.com',   'Contacto: Jeimmy Socha'),
  ('TRASAMER',               NULL,                           'Contacto: Jahir Muñoz'),
  ('JR LOGÍSTICA',           NULL,                           NULL),
  ('TRANS NUEVA COLOMBIA',   NULL,                           'Contacto: Cristhian Gomez'),
  ('PRACARGO',               NULL,                           NULL),
  ('GLOBAL LOGÍSTICA',       NULL,                           'Pendiente agregar a LogxIA'),
  ('VIGÍA',                  NULL,                           'Pendiente agregar a LogxIA')
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================
-- 2) OFERTAS (Módulo 1, necesaria para fn_adjudicar_oferta)
-- ============================================================
CREATE TABLE IF NOT EXISTS ofertas (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viaje_id          uuid NOT NULL REFERENCES viajes_consolidados(id) ON DELETE CASCADE,
  transportadora_id uuid REFERENCES transportadoras(id),
  usuario_id        uuid NOT NULL REFERENCES auth.users(id),
  precio_oferta     numeric NOT NULL CHECK (precio_oferta > 0),
  comentario        text,
  estado            text NOT NULL DEFAULT 'activa'
                    CHECK (estado IN ('activa', 'aceptada', 'rechazada', 'cancelada', 'vencida')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  cerrada_at        timestamptz
);

-- Solo una oferta activa por (viaje, usuario)
CREATE UNIQUE INDEX IF NOT EXISTS idx_ofertas_unique_activa
  ON ofertas(viaje_id, usuario_id)
  WHERE estado = 'activa';

CREATE INDEX IF NOT EXISTS idx_ofertas_viaje ON ofertas(viaje_id);
CREATE INDEX IF NOT EXISTS idx_ofertas_usuario ON ofertas(usuario_id);
CREATE INDEX IF NOT EXISTS idx_ofertas_transportadora ON ofertas(transportadora_id) WHERE transportadora_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ofertas_estado ON ofertas(estado);

ALTER TABLE ofertas ENABLE ROW LEVEL SECURITY;

-- Usuario lee sus ofertas; staff lee todas
DROP POLICY IF EXISTS "read_own_or_staff" ON ofertas;
CREATE POLICY "read_own_or_staff" ON ofertas
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() OR is_logxie_staff());

-- Usuario crea sus propias ofertas
DROP POLICY IF EXISTS "insert_own" ON ofertas;
CREATE POLICY "insert_own" ON ofertas
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = auth.uid());

-- Usuario cancela sus ofertas; staff actualiza cualquier (adjudicación)
DROP POLICY IF EXISTS "update_own_or_staff" ON ofertas;
CREATE POLICY "update_own_or_staff" ON ofertas
  FOR UPDATE TO authenticated
  USING (usuario_id = auth.uid() OR is_logxie_staff())
  WITH CHECK (usuario_id = auth.uid() OR is_logxie_staff());

DROP POLICY IF EXISTS "service_role_all" ON ofertas;
CREATE POLICY "service_role_all" ON ofertas
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================================
-- 3) INVITACIONES_SUBASTA
-- ============================================================
CREATE TABLE IF NOT EXISTS invitaciones_subasta (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viaje_id          uuid NOT NULL REFERENCES viajes_consolidados(id) ON DELETE CASCADE,
  transportadora_id uuid NOT NULL REFERENCES transportadoras(id),
  invitado_por      uuid REFERENCES auth.users(id),
  invitado_at       timestamptz NOT NULL DEFAULT now(),
  email_enviado_at  timestamptz,
  respondida_at     timestamptz,
  UNIQUE (viaje_id, transportadora_id)
);

CREATE INDEX IF NOT EXISTS idx_invitaciones_viaje ON invitaciones_subasta(viaje_id);
CREATE INDEX IF NOT EXISTS idx_invitaciones_transportadora ON invitaciones_subasta(transportadora_id);

ALTER TABLE invitaciones_subasta ENABLE ROW LEVEL SECURITY;

-- Staff ve todas; transportador ve solo las suyas
DROP POLICY IF EXISTS "read_own_or_staff" ON invitaciones_subasta;
CREATE POLICY "read_own_or_staff" ON invitaciones_subasta
  FOR SELECT TO authenticated
  USING (
    is_logxie_staff()
    OR EXISTS (
      SELECT 1 FROM perfiles p
      WHERE p.id = auth.uid()
        AND p.tipo = 'transportador'
        -- TODO: cuando perfiles.transportadora_id exista, usarlo acá
    )
  );

DROP POLICY IF EXISTS "service_role_all" ON invitaciones_subasta;
CREATE POLICY "service_role_all" ON invitaciones_subasta
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================================
-- 4) ALTER viajes_consolidados — campos de subasta/adjudicación
-- ============================================================
ALTER TABLE viajes_consolidados
  ADD COLUMN IF NOT EXISTS subasta_tipo       text DEFAULT 'abierta',
  ADD COLUMN IF NOT EXISTS publicado_at       timestamptz,
  ADD COLUMN IF NOT EXISTS adjudicado_at      timestamptz,
  ADD COLUMN IF NOT EXISTS oferta_ganadora_id uuid REFERENCES ofertas(id),
  ADD COLUMN IF NOT EXISTS adjudicacion_tipo  text,
  ADD COLUMN IF NOT EXISTS transportadora_id  uuid REFERENCES transportadoras(id);

-- CHECK constraints (drop + add para idempotencia)
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.viajes_consolidados'::regclass
      AND contype = 'c'
      AND conname IN ('viajes_subasta_tipo_check', 'viajes_adjudicacion_tipo_check')
  LOOP
    EXECUTE format('ALTER TABLE viajes_consolidados DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE viajes_consolidados
  ADD CONSTRAINT viajes_subasta_tipo_check
  CHECK (subasta_tipo IS NULL OR subasta_tipo IN ('abierta', 'cerrada'));

ALTER TABLE viajes_consolidados
  ADD CONSTRAINT viajes_adjudicacion_tipo_check
  CHECK (adjudicacion_tipo IS NULL OR adjudicacion_tipo IN ('subasta', 'directa'));

CREATE INDEX IF NOT EXISTS idx_viajes_transportadora ON viajes_consolidados(transportadora_id) WHERE transportadora_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_viajes_publicado ON viajes_consolidados(publicado_at) WHERE publicado_at IS NOT NULL;

-- ============================================================
-- 5) ALTER acciones_operador.accion — extender CHECK
--    Dropea cualquier CHECK sobre la columna accion y recrea.
--    (Postgres normaliza "IN (...)" a "= ANY(ARRAY[...])", por eso
--     matcheamos por nombre de columna en la definición, no por "IN".)
-- ============================================================
DO $$
DECLARE
  c record;
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
    'consolidar',
    'agregar_pedido',
    'quitar_pedido',
    'desconsolidar',
    'ajustar_precio',
    'publicar',
    'invitar',
    'asignar_directo',
    'adjudicar',
    'cancelar',
    'reasignar'
  ));

COMMIT;

-- ============================================================
-- Verificación rápida:
--   SELECT count(*) FROM transportadoras;  -- 7
--   SELECT count(*) FROM ofertas;          -- 0
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='viajes_consolidados' AND column_name IN
--      ('subasta_tipo','publicado_at','adjudicado_at','oferta_ganadora_id','adjudicacion_tipo','transportadora_id');
-- ============================================================

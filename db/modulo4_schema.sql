-- ============================================================
-- MÓDULO 4 — Control y Consolidación
-- Schema updates (paso 1 de 3)
--   1) clientes.plan_bpo
--   2) tabla acciones_operador (audit trail)
--
-- Precondición: perfiles.sql ya corrido (necesita is_logxie_staff()).
-- Idempotente — safe para re-run.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) clientes.plan_bpo
--    true  = Logxie opera por el cliente (BPO). Staff ve/actúa.
--    false = cliente self-service. Solo ve sus propios pedidos.
-- ------------------------------------------------------------
ALTER TABLE clientes
  ADD COLUMN IF NOT EXISTS plan_bpo boolean NOT NULL DEFAULT false;

-- AVGUST y FATECO son BPO hoy (Logxie consolida por ellos)
UPDATE clientes
  SET plan_bpo = true
  WHERE nombre IN ('AVGUST', 'FATECO') AND plan_bpo = false;

-- ------------------------------------------------------------
-- 2) tabla acciones_operador — audit trail Módulo 4
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS acciones_operador (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid REFERENCES auth.users(id),
  accion        text NOT NULL
                CHECK (accion IN (
                  'consolidar',
                  'desconsolidar',
                  'ajustar_precio',
                  'publicar',
                  'adjudicar',
                  'cancelar',
                  'reasignar'
                )),
  entidad_tipo  text NOT NULL
                CHECK (entidad_tipo IN ('viaje', 'pedido', 'oferta')),
  entidad_id    uuid NOT NULL,
  metadata      jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_acciones_user
  ON acciones_operador(user_id);
CREATE INDEX IF NOT EXISTS idx_acciones_entidad
  ON acciones_operador(entidad_tipo, entidad_id);
CREATE INDEX IF NOT EXISTS idx_acciones_created
  ON acciones_operador(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_acciones_accion
  ON acciones_operador(accion);

ALTER TABLE acciones_operador ENABLE ROW LEVEL SECURITY;

-- Logxie staff lee todo el audit
DROP POLICY IF EXISTS "logxie_staff_read" ON acciones_operador;
CREATE POLICY "logxie_staff_read" ON acciones_operador
  FOR SELECT TO authenticated
  USING (is_logxie_staff());

-- service_role puede todo (Postgres functions SECURITY DEFINER e intakes n8n)
DROP POLICY IF EXISTS "service_role_all" ON acciones_operador;
CREATE POLICY "service_role_all" ON acciones_operador
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMIT;

-- ============================================================
-- Verificación rápida:
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_name = 'clientes' AND column_name = 'plan_bpo';
--   SELECT count(*) FROM acciones_operador;
--   SELECT nombre, plan_bpo FROM clientes;
-- ============================================================

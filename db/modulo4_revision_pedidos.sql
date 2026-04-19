-- ============================================================
-- Módulo 4 — Revisión de pedidos (Tab "Nuevos")
--
-- Agrega la fase de VALIDACIÓN antes de consolidar. Un pedido recién
-- llegado queda en "Nuevos" hasta que un operador (o LogxIA) verifica
-- origen/destino/peso/contacto y lo marca como revisado.
--
-- Cambios:
--   - ALTER pedidos: +revisado_at, +revisado_por, +revision_notas
--   - fn_marcar_revisado(pedido_id, notas)
--   - fn_marcar_no_revisado(pedido_id, razon) — revertir
--   - CHECK acciones.accion extendido con 'revisar_pedido' y 'desmarcar_revision'
--   - UPDATE inicial: todos los pedidos históricos marcados como revisados
--     (evita que 3740 pedidos viejos aparezcan en "Nuevos")
--
-- Idempotente.
-- ============================================================

BEGIN;

-- 1) Columnas nuevas
ALTER TABLE pedidos
  ADD COLUMN IF NOT EXISTS revisado_at    timestamptz,
  ADD COLUMN IF NOT EXISTS revisado_por   uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS revision_notas text;

-- 2) Índices parciales — acelera queries por tab
CREATE INDEX IF NOT EXISTS idx_pedidos_nuevos
  ON pedidos(created_at) WHERE revisado_at IS NULL AND estado = 'sin_consolidar';

CREATE INDEX IF NOT EXISTS idx_pedidos_revisados_pendientes
  ON pedidos(fecha_cargue NULLS LAST) WHERE revisado_at IS NOT NULL AND estado = 'sin_consolidar';

-- 3) Extender CHECK acciones.accion
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
    'sync_viajes','sync_pedidos',
    'revisar_pedido','desmarcar_revision'
  ));

-- 4) fn_marcar_revisado
CREATE OR REPLACE FUNCTION fn_marcar_revisado(
  p_pedido_id uuid,
  p_notas     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede marcar pedidos revisados';
  END IF;

  SELECT estado INTO v_estado FROM pedidos WHERE id = p_pedido_id;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'pedido % no existe', p_pedido_id;
  END IF;

  UPDATE pedidos
  SET revisado_at = now(),
      revisado_por = auth.uid(),
      revision_notas = COALESCE(p_notas, revision_notas)
  WHERE id = p_pedido_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'revisar_pedido', 'pedido', p_pedido_id,
    jsonb_build_object('notas', p_notas, 'estado_al_momento', v_estado));
END;
$$;

-- 5) fn_marcar_no_revisado (revertir)
CREATE OR REPLACE FUNCTION fn_marcar_no_revisado(
  p_pedido_id uuid,
  p_razon     text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede desmarcar revisión';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para desmarcar revisión';
  END IF;

  SELECT estado INTO v_estado FROM pedidos WHERE id = p_pedido_id;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'pedido % no existe', p_pedido_id;
  END IF;
  IF v_estado <> 'sin_consolidar' THEN
    RAISE EXCEPTION 'Solo se desmarca pedidos sin_consolidar (actual: %)', v_estado;
  END IF;

  UPDATE pedidos
  SET revisado_at = NULL,
      revisado_por = NULL,
      revision_notas = COALESCE('DESMARCADO: ' || p_razon, revision_notas)
  WHERE id = p_pedido_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'desmarcar_revision', 'pedido', p_pedido_id,
    jsonb_build_object('razon', p_razon));
END;
$$;

-- 6) Backfill: marcar todos los pedidos históricos como revisados
--    Los 3740 existentes son data migrada que ya pasó por el flujo
--    operativo de AppSheet — no deben aparecer en "Nuevos".
UPDATE pedidos
SET revisado_at = COALESCE(created_at, now())
WHERE revisado_at IS NULL;

COMMIT;

-- Verificación
SELECT
  COUNT(*) FILTER (WHERE revisado_at IS NULL AND estado='sin_consolidar') AS nuevos_sin_revisar,
  COUNT(*) FILTER (WHERE revisado_at IS NOT NULL AND estado='sin_consolidar') AS revisados_pendientes_consolidar,
  COUNT(*) FILTER (WHERE estado NOT IN ('sin_consolidar','cancelado')) AS en_viaje_o_terminal,
  COUNT(*) AS total
FROM pedidos;

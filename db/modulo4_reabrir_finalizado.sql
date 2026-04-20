-- ============================================================
-- fn_reabrir_finalizado — deshace el cierre de un viaje
--
-- Transiciones:
--   finalizado  → confirmado (mantiene transportadora, proveedor, adjudicación)
--   pedidos entregado → asignado
--
-- Caso de uso: cerraste un viaje por error en el bulk-close.
-- No confundir con fn_reabrir_viaje (que va confirmado → pendiente,
-- libera proveedor).
--
-- Idempotente.
-- ============================================================

BEGIN;

-- Extender CHECK acciones.accion con 'reabrir_cierre'
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
    'revisar_pedido','desmarcar_revision',
    'cerrar','cerrar_batch','reabrir_cierre'
  ));

CREATE OR REPLACE FUNCTION fn_reabrir_finalizado(
  p_viaje_id uuid,
  p_razon    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
  v_pedidos_revertidos int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede reabrir un cierre';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida';
  END IF;

  SELECT estado INTO v_estado FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'viaje % no existe', p_viaje_id; END IF;
  IF v_estado <> 'finalizado' THEN
    RAISE EXCEPTION 'Solo se reabre el cierre de viajes finalizados (actual: %)', v_estado;
  END IF;

  -- Pedidos entregado → asignado (asumiendo que estaban asignado antes del cierre)
  UPDATE pedidos SET estado = 'asignado'
  WHERE viaje_id = p_viaje_id AND estado = 'entregado';
  GET DIAGNOSTICS v_pedidos_revertidos = ROW_COUNT;

  -- Viaje: finalizado → confirmado (mantiene proveedor y toda la adjudicación)
  UPDATE viajes_consolidados SET estado = 'confirmado' WHERE id = p_viaje_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'reabrir_cierre', 'viaje', p_viaje_id,
    jsonb_build_object(
      'pedidos_revertidos', v_pedidos_revertidos,
      'razon', p_razon
    ));
END;
$$;

COMMIT;

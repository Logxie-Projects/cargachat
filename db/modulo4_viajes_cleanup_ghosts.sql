-- ============================================================
-- fn_viajes_cleanup_ghosts(refs_actuales text[])
--
-- Cancela viajes fantasma: los que están en BD con fuente='sheet_asignados'
-- + estado='pendiente' + proveedor vacío pero YA NO aparecen en el CSV del
-- Sheet (Bernardo los eliminó en AppSheet).
--
-- Safety: solo pendientes sin proveedor. Nunca toca viajes con adjudicación
-- Netfleet, ni ofertas activas, ni estados terminales.
--
-- Se llama al final del Sync pasando el array de viaje_refs del CSV.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_viajes_cleanup_ghosts(refs_actuales text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_cancelados int;
  v_ids_cancelados jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede limpiar viajes fantasma';
  END IF;

  -- Snapshot antes
  SELECT jsonb_agg(viaje_ref) INTO v_ids_cancelados
  FROM viajes_consolidados
  WHERE fuente = 'sheet_asignados'
    AND estado = 'pendiente'
    AND (proveedor IS NULL OR trim(proveedor) = '')
    AND NOT (viaje_ref = ANY(refs_actuales))
    AND oferta_ganadora_id IS NULL
    AND transportadora_id IS NULL;

  UPDATE viajes_consolidados
  SET estado = 'cancelado',
      estado_original = 'GHOST: eliminado del Sheet'
  WHERE fuente = 'sheet_asignados'
    AND estado = 'pendiente'
    AND (proveedor IS NULL OR trim(proveedor) = '')
    AND NOT (viaje_ref = ANY(refs_actuales))
    AND oferta_ganadora_id IS NULL
    AND transportadora_id IS NULL;
  GET DIAGNOSTICS c_cancelados = ROW_COUNT;

  -- Pedidos de esos viajes: liberarlos a sin_consolidar sin viaje_id
  UPDATE pedidos SET estado = 'sin_consolidar', viaje_id = NULL
  WHERE viaje_id IN (
    SELECT id FROM viajes_consolidados
    WHERE estado = 'cancelado' AND estado_original = 'GHOST: eliminado del Sheet'
  );

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cancelar', 'viaje', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'op', 'cleanup_ghosts',
      'cancelados', c_cancelados,
      'viaje_refs', v_ids_cancelados
    ));

  RETURN jsonb_build_object(
    'cancelados', c_cancelados,
    'viaje_refs', v_ids_cancelados
  );
END;
$$;

COMMIT;

-- ============================================================
-- fn_auto_revisar_con_viaje()
--
-- Cleanup one-click: marca como revisados TODOS los pedidos que
-- siguen como "Nuevos" (revisado_at IS NULL) pero ya tienen un
-- viaje_id asignado. Usa caso: tras un reset masivo a "Nuevos",
-- los linkers v3+v4 ya habían matcheado algunos a RT-TOTAL en
-- ASIGNADOS — esos no son realmente nuevos.
--
-- revision_notas documenta el viaje_ref al que ya estaban linkeados
-- para trazabilidad.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_auto_revisar_con_viaje()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_candidatos   int;
  c_actualizados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede ejecutar auto-revisar';
  END IF;

  SELECT COUNT(*) INTO c_candidatos
    FROM pedidos
    WHERE revisado_at IS NULL AND viaje_id IS NOT NULL;

  UPDATE pedidos p
  SET revisado_at    = now(),
      revisado_por   = auth.uid(),
      estado         = CASE WHEN p.estado = 'sin_consolidar' THEN 'consolidado' ELSE p.estado END,
      revision_notas = 'Auto-revisado: ya consolidado en viaje ' ||
        COALESCE((SELECT viaje_ref FROM viajes_consolidados WHERE id = p.viaje_id), p.viaje_id::text)
  WHERE p.revisado_at IS NULL
    AND p.viaje_id IS NOT NULL;

  GET DIAGNOSTICS c_actualizados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'revisar_pedido', 'pedido',
    '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'op',           'auto_revisar_con_viaje',
      'candidatos',   c_candidatos,
      'actualizados', c_actualizados
    ));

  RETURN jsonb_build_object(
    'candidatos',   c_candidatos,
    'actualizados', c_actualizados
  );
END;
$$;

COMMIT;

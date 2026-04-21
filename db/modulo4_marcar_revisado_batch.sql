-- ============================================================
-- fn_pedidos_marcar_revisado_batch
--
-- Bulk version de fn_marcar_revisado. Mueve N pedidos de "Nuevos"
-- (revisado_at IS NULL) a "Sin consolidar" (revisado_at = now()),
-- con nota opcional en revision_notas para identificarlos después.
--
-- Solo afecta pedidos con revisado_at IS NULL (no toca los ya
-- revisados). No cambia estado ni viaje_id.
--
-- Use case: limpiar el tab Nuevos cuando hay pedidos que ya
-- consolidaste en el Sheet pero el linker no detectó por refs raras.
-- Quedan en Sin consolidar pendientes de asociación manual via 🔗.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_pedidos_marcar_revisado_batch(
  p_pedido_ids uuid[],
  p_notas      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_marcados int;
  c_skip_ya_revisados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede marcar pedidos revisados';
  END IF;

  IF p_pedido_ids IS NULL OR array_length(p_pedido_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Lista de pedidos vacía';
  END IF;

  -- Skip los ya revisados
  SELECT COUNT(*) INTO c_skip_ya_revisados
    FROM pedidos
    WHERE id = ANY(p_pedido_ids) AND revisado_at IS NOT NULL;

  UPDATE pedidos
  SET revisado_at    = now(),
      revisado_por   = auth.uid(),
      revision_notas = CASE
        WHEN p_notas IS NULL OR trim(p_notas) = '' THEN revision_notas
        ELSE p_notas
      END
  WHERE id = ANY(p_pedido_ids)
    AND revisado_at IS NULL;
  GET DIAGNOSTICS c_marcados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'revisar_pedido', 'pedido',
    '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'op',                 'bulk',
      'marcados',           c_marcados,
      'skip_ya_revisados',  c_skip_ya_revisados,
      'notas',              p_notas,
      'pedido_ids',         to_jsonb(p_pedido_ids)
    ));

  RETURN jsonb_build_object(
    'marcados',           c_marcados,
    'skip_ya_revisados',  c_skip_ya_revisados
  );
END;
$$;

COMMIT;

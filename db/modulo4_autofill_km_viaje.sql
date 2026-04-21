-- ============================================================
-- fn_autofill_km_viaje(viaje_id, km)
--
-- Escribe km_total en un viaje SOLO si es NULL. Idempotente — el primer
-- cliente (transportador o operador) que calcula el km lo persiste.
--
-- Usa-case: viajes del Sheet que llegan sin km → transportador.html
-- calcula haversine × 1.3 y llama este RPC para persistir.
--
-- Safety: no sobreescribe valores existentes. RLS: cualquier usuario
-- authenticated puede llamar (no es dato sensible).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_autofill_km_viaje(
  p_viaje_id uuid,
  p_km       numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_km_actual numeric;
  v_updated   boolean := false;
BEGIN
  -- Cualquier usuario authenticated puede llamar (no requiere logxie_staff)
  IF auth.uid() IS NULL
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Requiere autenticación';
  END IF;

  IF p_km IS NULL OR p_km <= 0 THEN
    RETURN jsonb_build_object('updated', false, 'reason', 'km inválido');
  END IF;

  SELECT km_total INTO v_km_actual FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_km_actual IS NOT NULL THEN
    RETURN jsonb_build_object('updated', false, 'reason', 'km ya existe', 'km_actual', v_km_actual);
  END IF;

  UPDATE viajes_consolidados SET km_total = p_km WHERE id = p_viaje_id AND km_total IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN jsonb_build_object('updated', v_updated, 'km_nuevo', p_km);
END;
$$;

-- Permitir que usuarios authenticated lo llamen
GRANT EXECUTE ON FUNCTION fn_autofill_km_viaje(uuid, numeric) TO authenticated;

COMMIT;

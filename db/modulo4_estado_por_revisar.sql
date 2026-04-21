-- ============================================================
-- Estado nuevo: 'por_revisar'
--
-- Bucket separado de "Sin consolidar" (área de trabajo) para parquear
-- pedidos que aparecieron como Nuevos pero ya están consolidados en
-- el Sheet con refs no estándar. Quedan ahí esperando asociación
-- manual via 🔗 sin contaminar la cola de trabajo.
--
-- Cambios:
--   1. fn_pedidos_cambiar_estado_batch acepta 'por_revisar' en whitelist
--   2. fn_pedido_asociar_viaje promueve 'por_revisar' → 'consolidado'
--      (igual que ya hace con 'sin_consolidar')
-- ============================================================

BEGIN;

-- 1) Whitelist en cambiar_estado_batch
CREATE OR REPLACE FUNCTION fn_pedidos_cambiar_estado_batch(
  p_pedido_ids  uuid[],
  p_nuevo_estado text,
  p_razon       text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cambiados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede cambiar estado de pedidos';
  END IF;

  IF p_nuevo_estado NOT IN ('sin_consolidar','por_revisar','consolidado','asignado','en_ruta','entregado','entregado_novedad','rechazado','cancelado') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_nuevo_estado;
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida';
  END IF;

  UPDATE pedidos SET estado = p_nuevo_estado
  WHERE id = ANY(p_pedido_ids);
  GET DIAGNOSTICS v_cambiados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cambiar_estado_pedido', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'pedido_ids',   to_jsonb(p_pedido_ids),
      'nuevo_estado', p_nuevo_estado,
      'cambiados',    v_cambiados,
      'razon',        p_razon
    ));

  RETURN jsonb_build_object('cambiados', v_cambiados);
END;
$$;

-- 2) Asociar viaje promueve también por_revisar → consolidado
CREATE OR REPLACE FUNCTION fn_pedido_asociar_viaje(
  p_pedido_id uuid,
  p_viaje_id  uuid,
  p_razon     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado_actual    text;
  v_viaje_id_actual  uuid;
  v_viaje_ref        text;
  v_estado_nuevo     text;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede asociar pedidos a viajes';
  END IF;

  SELECT estado, viaje_id INTO v_estado_actual, v_viaje_id_actual
    FROM pedidos WHERE id = p_pedido_id;
  IF v_estado_actual IS NULL THEN
    RAISE EXCEPTION 'Pedido % no existe', p_pedido_id;
  END IF;

  SELECT viaje_ref INTO v_viaje_ref FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_ref IS NULL THEN
    RAISE EXCEPTION 'Viaje % no existe', p_viaje_id;
  END IF;

  v_estado_nuevo := CASE
    WHEN v_estado_actual IN ('sin_consolidar','por_revisar') THEN 'consolidado'
    ELSE v_estado_actual
  END;

  UPDATE pedidos
  SET viaje_id        = p_viaje_id,
      estado          = v_estado_nuevo,
      revisado_at     = COALESCE(revisado_at, now()),
      revisado_por    = COALESCE(revisado_por, auth.uid()),
      revision_notas  = 'Asociado manual a ' || v_viaje_ref ||
                        CASE WHEN p_razon IS NOT NULL AND trim(p_razon) <> ''
                             THEN ' · ' || p_razon ELSE '' END
  WHERE id = p_pedido_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'asociar_viaje', 'pedido', p_pedido_id,
    jsonb_build_object(
      'viaje_id_anterior', v_viaje_id_actual,
      'viaje_id_nuevo',    p_viaje_id,
      'viaje_ref',         v_viaje_ref,
      'estado_anterior',   v_estado_actual,
      'estado_nuevo',      v_estado_nuevo,
      'razon',             p_razon
    ));

  RETURN jsonb_build_object(
    'pedido_id',  p_pedido_id,
    'viaje_id',   p_viaje_id,
    'viaje_ref',  v_viaje_ref,
    'estado',     v_estado_nuevo
  );
END;
$$;

COMMIT;

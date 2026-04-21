-- ============================================================
-- fn_pedido_asociar_viaje + fn_pedido_desasociar_viaje
--
-- Permite al operador linkear/deslinkear manualmente un pedido a
-- un viaje cuando el linker automático (v3/v4) no lo catchea o
-- cuando hay refs no estándar (DEVOLUCION, ULTIMA MILLA, BL. ...).
--
-- Asociar: setea viaje_id, promueve estado sin_consolidar→consolidado,
--          marca como revisado, guarda razón en revision_notas y audit.
-- Desasociar: limpia viaje_id, baja estado consolidado→sin_consolidar
--             (no toca asignado/en_ruta/entregado), audit.
-- ============================================================

BEGIN;

-- Extender CHECK acciones_operador
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
    'cerrar','cerrar_batch','reabrir_cierre',
    'cancelar_pedidos_batch','resetear_pedidos_batch','clonar_pedido',
    'editar_pedido','cambiar_estado_pedido','eliminar_pedido',
    'run_linkers',
    'asociar_viaje','desasociar_viaje'
  ));

-- ============================================================
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

  -- Promover estado si está en sin_consolidar; resto se mantiene
  v_estado_nuevo := CASE
    WHEN v_estado_actual = 'sin_consolidar' THEN 'consolidado'
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

-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedido_desasociar_viaje(
  p_pedido_id uuid,
  p_razon     text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado_actual    text;
  v_viaje_id_actual  uuid;
  v_estado_nuevo     text;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede desasociar pedidos';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para desasociar';
  END IF;

  SELECT estado, viaje_id INTO v_estado_actual, v_viaje_id_actual
    FROM pedidos WHERE id = p_pedido_id;
  IF v_estado_actual IS NULL THEN
    RAISE EXCEPTION 'Pedido % no existe', p_pedido_id;
  END IF;
  IF v_viaje_id_actual IS NULL THEN
    RAISE EXCEPTION 'Pedido no tiene viaje asignado';
  END IF;

  -- Solo bajar estado si era consolidado; no tocar asignado/en_ruta/entregado
  v_estado_nuevo := CASE
    WHEN v_estado_actual = 'consolidado' THEN 'sin_consolidar'
    ELSE v_estado_actual
  END;

  UPDATE pedidos
  SET viaje_id       = NULL,
      estado         = v_estado_nuevo,
      revision_notas = 'Desasociado manual: ' || p_razon
  WHERE id = p_pedido_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'desasociar_viaje', 'pedido', p_pedido_id,
    jsonb_build_object(
      'viaje_id_anterior', v_viaje_id_actual,
      'estado_anterior',   v_estado_actual,
      'estado_nuevo',      v_estado_nuevo,
      'razon',             p_razon
    ));

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id,
    'estado',    v_estado_nuevo
  );
END;
$$;

COMMIT;

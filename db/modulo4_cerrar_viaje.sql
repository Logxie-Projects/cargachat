-- ============================================================
-- fn_cerrar_viaje + fn_cerrar_viajes_batch
--
-- Cierra viajes (los pasa a 'finalizado'). Para limpieza de data
-- histórica: 508 viajes quedaron en estado='confirmado' porque en
-- AppSheet nunca pasaron de ASIGNADO a EJECUTADO/FINALIZADO.
--
-- Sirve también para el flujo normal: un viaje confirmado (o en_ruta,
-- o entregado) que se considera cerrado/facturado → finalizado.
--
-- Idempotente.
-- ============================================================

BEGIN;

-- Extender CHECK acciones.accion con 'cerrar'
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
    'cerrar','cerrar_batch'
  ));

-- fn_cerrar_viaje: single
CREATE OR REPLACE FUNCTION fn_cerrar_viaje(
  p_viaje_id uuid,
  p_razon    text DEFAULT NULL
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
    RAISE EXCEPTION 'Solo logxie_staff puede cerrar viajes';
  END IF;

  SELECT estado INTO v_estado FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'viaje % no existe', p_viaje_id; END IF;
  IF v_estado IN ('finalizado','cancelado') THEN RETURN; END IF;
  IF v_estado NOT IN ('confirmado','en_ruta','entregado') THEN
    RAISE EXCEPTION 'No se puede cerrar viaje en estado % (debe ser confirmado/en_ruta/entregado)', v_estado;
  END IF;

  UPDATE viajes_consolidados SET estado='finalizado' WHERE id = p_viaje_id;

  -- Pedidos del viaje → entregado si no estaban en estado terminal
  UPDATE pedidos SET estado='entregado'
   WHERE viaje_id = p_viaje_id
     AND estado NOT IN ('entregado','entregado_novedad','rechazado','cancelado');

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cerrar', 'viaje', p_viaje_id,
    jsonb_build_object('estado_anterior', v_estado, 'razon', p_razon));
END;
$$;

-- fn_cerrar_viajes_batch: cierra N viajes en una transacción
CREATE OR REPLACE FUNCTION fn_cerrar_viajes_batch(
  p_viaje_ids uuid[],
  p_razon     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  c_cerrados int := 0;
  c_ya_cerrados int := 0;
  c_invalidos int := 0;
  errors jsonb := '[]'::jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede cerrar viajes';
  END IF;

  FOREACH v_id IN ARRAY p_viaje_ids LOOP
    BEGIN
      PERFORM fn_cerrar_viaje(v_id, p_razon);
      c_cerrados := c_cerrados + 1;
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE '%finalizado%' OR SQLERRM LIKE '%cancelado%' THEN
        c_ya_cerrados := c_ya_cerrados + 1;
      ELSE
        c_invalidos := c_invalidos + 1;
        IF jsonb_array_length(errors) < 5 THEN
          errors := errors || jsonb_build_object('viaje_id', v_id, 'error', SQLERRM);
        END IF;
      END IF;
    END;
  END LOOP;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cerrar_batch', 'viaje', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'cerrados', c_cerrados,
      'ya_cerrados', c_ya_cerrados,
      'invalidos', c_invalidos,
      'razon', p_razon,
      'errors', errors,
      'total_input', array_length(p_viaje_ids, 1)
    ));

  RETURN jsonb_build_object(
    'cerrados', c_cerrados,
    'ya_cerrados', c_ya_cerrados,
    'invalidos', c_invalidos,
    'errors', errors
  );
END;
$$;

COMMIT;

-- ============================================================
-- fn_sync_viajes_batch — permitir UPDATE de campos monetarios
-- en viajes con estados terminales (en_ruta/entregado/finalizado/cancelado).
--
-- Antes: CONTINUE skippeaba completamente. Ahora:
--   - estado NO se cambia (respeta decisión operativa)
--   - viaje_id / proveedor / transportadora_id se respetan
--   - SÍ se actualizan: flete_total, peso_kg, valor_mercancia, km_total,
--     cantidad_pedidos, contenedores/cajas/etc, fecha_cargue
--     + estado_original + raw_payload (para auditoría)
--
-- Use case: cerraste un viaje antes de tener el flete final, después lo
-- completaste en el Sheet. Sync lo actualiza sin resucitar el viaje.
--
-- Y se crea fn_reabrir_cancelado: para resucitar un cancelado → pendiente.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_sync_viajes_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row             jsonb;
  v_viaje_ref       text;
  v_existing_id     uuid;
  v_existing_estado text;
  v_existing_fuente text;
  v_cliente_id      uuid;
  v_estado_norm     text;
  v_estado_orig     text;

  c_insertados              int := 0;
  c_actualizados            int := 0;
  c_saltados_netfleet       int := 0;
  c_actualizados_monetario  int := 0;  -- nuevo counter
  c_marcados_cancelado      int := 0;
  c_errores                 int := 0;
  err_samples               jsonb := '[]'::jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff, service_role o postgres pueden disparar sync';
  END IF;

  IF jsonb_typeof(p_payload) <> 'array' THEN
    RAISE EXCEPTION 'payload debe ser un array JSON';
  END IF;

  FOR v_row IN SELECT jsonb_array_elements(p_payload) LOOP
    BEGIN
      v_viaje_ref := trim(v_row->>'viaje_ref');
      IF v_viaje_ref IS NULL OR v_viaje_ref = '' THEN CONTINUE; END IF;

      SELECT id, estado, fuente INTO v_existing_id, v_existing_estado, v_existing_fuente
        FROM viajes_consolidados WHERE viaje_ref = v_viaje_ref LIMIT 1;

      v_estado_orig := v_row->>'estado_sheet';
      v_estado_norm := _norm_estado_viaje(v_estado_orig);
      v_cliente_id := COALESCE(
        (v_row->>'cliente_id')::uuid,
        _cliente_id_por_empresa(v_row->>'empresa')
      );

      IF v_existing_id IS NOT NULL THEN
        -- Regla 1: Netfleet gana (siempre)
        IF v_existing_fuente = 'netfleet' THEN
          c_saltados_netfleet := c_saltados_netfleet + 1;
          CONTINUE;
        END IF;

        -- Regla 2 (NUEVA): estados terminales permiten UPDATE monetario,
        -- pero nunca cambiar estado ni relaciones (proveedor, transportadora).
        IF v_existing_estado IN ('en_ruta','entregado','finalizado','cancelado') THEN
          UPDATE viajes_consolidados SET
            flete_total         = COALESCE((v_row->>'flete_total')::numeric,     flete_total),
            km_total            = COALESCE((v_row->>'km_total')::numeric,        km_total),
            peso_kg             = COALESCE((v_row->>'peso_kg')::numeric,         peso_kg),
            valor_mercancia     = COALESCE((v_row->>'valor_mercancia')::numeric, valor_mercancia),
            cantidad_pedidos    = COALESCE((v_row->>'cantidad_pedidos')::int,    cantidad_pedidos),
            contenedores        = COALESCE((v_row->>'contenedores')::int,        contenedores),
            cajas               = COALESCE((v_row->>'cajas')::int,               cajas),
            bidones             = COALESCE((v_row->>'bidones')::int,             bidones),
            canecas             = COALESCE((v_row->>'canecas')::int,             canecas),
            unidades_sueltas    = COALESCE((v_row->>'unidades_sueltas')::int,    unidades_sueltas),
            fecha_cargue        = COALESCE((v_row->>'fecha_cargue')::timestamptz, fecha_cargue),
            fecha_consolidacion = COALESCE((v_row->>'fecha_consolidacion')::timestamptz, fecha_consolidacion),
            estado_original     = v_estado_orig,  -- mantiene el texto raw del Sheet
            raw_payload         = v_row::text
          WHERE id = v_existing_id;
          c_actualizados_monetario := c_actualizados_monetario + 1;
          CONTINUE;
        END IF;

        -- Regla 3: si Sheet dice cancelado y viaje activo, propagar
        IF v_estado_norm = 'cancelado' THEN
          UPDATE viajes_consolidados
          SET estado = 'cancelado', estado_original = v_estado_orig
          WHERE id = v_existing_id;
          c_marcados_cancelado := c_marcados_cancelado + 1;
          CONTINUE;
        END IF;

        -- UPDATE completo para viajes no terminales
        UPDATE viajes_consolidados SET
          empresa             = COALESCE(_norm_empresa(v_row->>'empresa'), empresa),
          zona                = COALESCE(v_row->>'zona',                zona),
          origen              = COALESCE(v_row->>'origen',              origen),
          destino             = COALESCE(v_row->>'destino',             destino),
          cantidad_pedidos    = COALESCE((v_row->>'cantidad_pedidos')::int, cantidad_pedidos),
          consecutivos        = COALESCE(v_row->>'consecutivos',        consecutivos),
          km_total            = COALESCE((v_row->>'km_total')::numeric, km_total),
          flete_total         = COALESCE((v_row->>'flete_total')::numeric, flete_total),
          peso_kg             = COALESCE((v_row->>'peso_kg')::numeric,  peso_kg),
          valor_mercancia     = COALESCE((v_row->>'valor_mercancia')::numeric, valor_mercancia),
          contenedores        = COALESCE((v_row->>'contenedores')::int, contenedores),
          cajas               = COALESCE((v_row->>'cajas')::int,        cajas),
          bidones             = COALESCE((v_row->>'bidones')::int,      bidones),
          canecas             = COALESCE((v_row->>'canecas')::int,      canecas),
          unidades_sueltas    = COALESCE((v_row->>'unidades_sueltas')::int, unidades_sueltas),
          proveedor           = COALESCE(v_row->>'proveedor',           proveedor),
          tipo_vehiculo       = COALESCE(v_row->>'tipo_vehiculo',       tipo_vehiculo),
          placa               = COALESCE(v_row->>'placa',               placa),
          conductor_nombre    = COALESCE(v_row->>'conductor_nombre',    conductor_nombre),
          conductor_id        = COALESCE(v_row->>'conductor_id',        conductor_id),
          fecha_cargue        = COALESCE((v_row->>'fecha_cargue')::timestamptz, fecha_cargue),
          fecha_consolidacion = COALESCE((v_row->>'fecha_consolidacion')::timestamptz, fecha_consolidacion),
          observaciones       = COALESCE(v_row->>'observaciones',       observaciones),
          foto_cargue         = COALESCE(v_row->>'foto_cargue',         foto_cargue),
          soporte_entrega     = COALESCE(v_row->>'soporte_entrega',     soporte_entrega),
          confirma_vehiculo   = COALESCE(v_row->>'confirma_vehiculo',   confirma_vehiculo),
          cliente_id          = COALESCE(v_cliente_id,                  cliente_id),
          estado              = v_estado_norm,
          estado_original     = v_estado_orig,
          raw_payload         = v_row::text
        WHERE id = v_existing_id;
        c_actualizados := c_actualizados + 1;
      ELSE
        INSERT INTO viajes_consolidados (
          viaje_ref, cliente_id, empresa, zona, origen, destino,
          cantidad_pedidos, consecutivos, km_total, flete_total,
          peso_kg, valor_mercancia, contenedores, cajas, bidones,
          canecas, unidades_sueltas, proveedor, tipo_vehiculo, placa,
          conductor_nombre, conductor_id, fecha_cargue, fecha_consolidacion,
          observaciones, foto_cargue, soporte_entrega, confirma_vehiculo,
          estado, estado_original, fuente, raw_payload
        ) VALUES (
          v_viaje_ref, v_cliente_id, _norm_empresa(v_row->>'empresa'), v_row->>'zona',
          v_row->>'origen', v_row->>'destino',
          (v_row->>'cantidad_pedidos')::int, v_row->>'consecutivos',
          (v_row->>'km_total')::numeric, (v_row->>'flete_total')::numeric,
          (v_row->>'peso_kg')::numeric, (v_row->>'valor_mercancia')::numeric,
          COALESCE((v_row->>'contenedores')::int, 0), COALESCE((v_row->>'cajas')::int, 0),
          COALESCE((v_row->>'bidones')::int, 0), COALESCE((v_row->>'canecas')::int, 0),
          COALESCE((v_row->>'unidades_sueltas')::int, 0),
          v_row->>'proveedor', v_row->>'tipo_vehiculo', v_row->>'placa',
          v_row->>'conductor_nombre', v_row->>'conductor_id',
          (v_row->>'fecha_cargue')::timestamptz,
          (v_row->>'fecha_consolidacion')::timestamptz,
          v_row->>'observaciones',
          v_row->>'foto_cargue', v_row->>'soporte_entrega', v_row->>'confirma_vehiculo',
          v_estado_norm, v_estado_orig, 'sheet_asignados', v_row::text
        );
        c_insertados := c_insertados + 1;
      END IF;
    EXCEPTION WHEN others THEN
      c_errores := c_errores + 1;
      IF jsonb_array_length(err_samples) < 5 THEN
        err_samples := err_samples || jsonb_build_object(
          'viaje_ref', v_viaje_ref, 'error', SQLERRM
        );
      END IF;
    END;
  END LOOP;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'sync_viajes', 'viaje', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'insertados', c_insertados,
      'actualizados', c_actualizados,
      'saltados_netfleet', c_saltados_netfleet,
      'actualizados_monetario', c_actualizados_monetario,
      'marcados_cancelado', c_marcados_cancelado,
      'errores', c_errores,
      'err_samples', err_samples,
      'total_input', jsonb_array_length(p_payload)
    ));

  RETURN jsonb_build_object(
    'insertados', c_insertados,
    'actualizados', c_actualizados,
    'saltados_netfleet', c_saltados_netfleet,
    'actualizados_monetario', c_actualizados_monetario,
    'marcados_cancelado', c_marcados_cancelado,
    'errores', c_errores,
    'err_samples', err_samples,
    'total_input', jsonb_array_length(p_payload)
  );
END;
$$;

-- ============================================================
-- fn_reabrir_cancelado — resucitar un cancelado → pendiente
-- ============================================================
CREATE OR REPLACE FUNCTION fn_reabrir_cancelado(
  p_viaje_id uuid,
  p_razon    text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado_actual text;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role') THEN
    RAISE EXCEPTION 'Solo logxie_staff';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida';
  END IF;

  SELECT estado INTO v_estado_actual FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_estado_actual IS NULL THEN RAISE EXCEPTION 'Viaje no existe'; END IF;
  IF v_estado_actual <> 'cancelado' THEN
    RAISE EXCEPTION 'Solo viajes cancelados pueden resucitarse con esta función (actual: %)', v_estado_actual;
  END IF;

  UPDATE viajes_consolidados SET estado = 'pendiente' WHERE id = p_viaje_id;

  -- Pedidos del viaje: sin_consolidar si estaban cancelado por cascade; o mantienen si ya cambiaron
  UPDATE pedidos SET estado = 'consolidado'
    WHERE viaje_id = p_viaje_id AND estado = 'cancelado';

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'reabrir', 'viaje', p_viaje_id,
    jsonb_build_object(
      'estado_anterior', 'cancelado',
      'estado_nuevo',    'pendiente',
      'razon',           p_razon
    ));

  RETURN jsonb_build_object('ok', true, 'estado_nuevo', 'pendiente');
END;
$$;

COMMIT;

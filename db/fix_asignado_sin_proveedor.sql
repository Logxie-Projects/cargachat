-- ============================================================
-- Fix: si Sheet dice ESTADO='ASIGNADO' pero proveedor vacío,
-- el viaje NO está realmente adjudicado — es biddable. Mapear a
-- 'pendiente' para que aparezca en transportador.html.
-- ============================================================

BEGIN;

-- Sobrescribir fn_sync_viajes_batch solo el bloque que setea estado.
-- En vez de refactorizar _norm_estado_viaje (no conoce proveedor),
-- agregamos un post-procesamiento en la función sync: si el estado
-- normalizado terminó en 'confirmado' Y proveedor está vacío, forzar
-- a 'pendiente'.

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
  v_proveedor       text;

  c_insertados              int := 0;
  c_actualizados            int := 0;
  c_saltados_netfleet       int := 0;
  c_actualizados_monetario  int := 0;
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
      v_proveedor   := NULLIF(trim(coalesce(v_row->>'proveedor', '')), '');
      v_cliente_id  := COALESCE(
        (v_row->>'cliente_id')::uuid,
        _cliente_id_por_empresa(v_row->>'empresa')
      );

      -- FIX: Sheet dice ASIGNADO / CONFIRMADO pero proveedor vacío
      -- → aún no hay adjudicación real, es biddable → mapear a pendiente
      IF v_estado_norm IN ('confirmado') AND v_proveedor IS NULL THEN
        v_estado_norm := 'pendiente';
      END IF;

      IF v_existing_id IS NOT NULL THEN
        IF v_existing_fuente = 'netfleet' THEN
          c_saltados_netfleet := c_saltados_netfleet + 1;
          CONTINUE;
        END IF;

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
            estado_original     = v_estado_orig,
            raw_payload         = v_row::text
          WHERE id = v_existing_id;
          c_actualizados_monetario := c_actualizados_monetario + 1;
          CONTINUE;
        END IF;

        IF v_estado_norm = 'cancelado' THEN
          UPDATE viajes_consolidados
          SET estado = 'cancelado', estado_original = v_estado_orig
          WHERE id = v_existing_id;
          c_marcados_cancelado := c_marcados_cancelado + 1;
          CONTINUE;
        END IF;

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
          proveedor           = v_proveedor,  -- puede ser NULL (vacío en sheet)
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
          v_proveedor, v_row->>'tipo_vehiculo', v_row->>'placa',
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

-- Fix en caliente para el viaje de prueba
-- (reabrir finalizado + forzar estado pendiente + limpiar pedidos cancelados→consolidado)
UPDATE pedidos SET estado='consolidado'
  WHERE viaje_id = (SELECT id FROM viajes_consolidados WHERE viaje_ref='RT-TOTAL-1776788580627')
    AND estado = 'entregado';  -- reset a consolidado para que puedan volver a ofertarse

UPDATE viajes_consolidados SET estado='pendiente', publicado_at=NULL
 WHERE viaje_ref = 'RT-TOTAL-1776788580627';

COMMIT;

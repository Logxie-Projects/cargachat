-- ============================================================
-- MÓDULO 4 / M2 — Sync unidireccional Sheets → Netfleet
--
-- Dos funciones que hacen UPSERT batch desde un payload JSONB:
--   fn_sync_viajes_batch   — viajes ASIGNADOS → viajes_consolidados
--   fn_sync_pedidos_batch  — Base_inicio-def  → pedidos
--
-- Reglas:
--   - Netfleet gana: viajes con fuente='netfleet' → skip (no se tocan)
--   - Estados terminales (en_ruta, entregado, finalizado) → skip
--   - Sheet nunca elimina: si estado_sheet='Cancelado' → propaga
--   - Audit: acción 'sync_viajes' / 'sync_pedidos' con counters
--
-- Input JSON esperado por viaje (ejemplo):
--   {"viaje_ref":"RT-TOTAL-xxx","empresa":"AVGUST","origen":"...",
--    "destino":"...","proveedor":"ENTRAPETROL","flete_total":2500000,
--    "peso_kg":10000,"fecha_cargue":"2026-04-19","consecutivos":"RM-1,RM-2",
--    "estado_sheet":"EJECUTADO", ...}
--
-- Precondiciones: perfiles.sql + modulo4_schema.sql + fn is_logxie_staff
-- Idempotente (CREATE OR REPLACE).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- Extender CHECK de acciones_operador.accion con 'sync_viajes' y 'sync_pedidos'
-- ------------------------------------------------------------
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
    'run_linkers'
  ));

-- ------------------------------------------------------------
-- Helper: normalizar estado crudo del Sheet a nuestros estados canónicos
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _norm_estado_viaje(raw text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE upper(trim(coalesce(raw, '')))
    WHEN '' THEN 'pendiente'
    WHEN 'PENDIENTE' THEN 'pendiente'
    WHEN 'EN CONSOLIDACION' THEN 'pendiente'
    WHEN 'CONFIRMADO' THEN 'confirmado'
    WHEN 'ASIGNADO' THEN 'confirmado'
    WHEN 'EN RUTA' THEN 'en_ruta'
    WHEN 'EN TRANSITO' THEN 'en_ruta'
    WHEN 'EJECUTADO' THEN 'entregado'
    WHEN 'ENTREGADO' THEN 'entregado'
    WHEN 'FINALIZADO' THEN 'finalizado'
    WHEN 'CERRADO' THEN 'finalizado'
    WHEN 'CANCELADO' THEN 'cancelado'
    ELSE 'pendiente'
  END;
$$;

CREATE OR REPLACE FUNCTION _norm_estado_pedido(raw text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE upper(trim(coalesce(raw, '')))
    WHEN '' THEN 'sin_consolidar'
    WHEN 'PENDIENTE' THEN 'sin_consolidar'
    WHEN 'SIN CONSOLIDAR' THEN 'sin_consolidar'
    -- 'EN PROCESO' en el Sheet = pedido pendiente de consolidar (no "ya consolidado").
    -- El estado real consolidado lo determina el linker cuando matchea a un RT-TOTAL.
    WHEN 'EN PROCESO' THEN 'sin_consolidar'
    WHEN 'CONSOLIDADO' THEN 'consolidado'
    WHEN 'ASIGNADO' THEN 'asignado'
    WHEN 'EN RUTA' THEN 'en_ruta'
    WHEN 'EJECUTADO' THEN 'entregado'
    WHEN 'ENTREGADO' THEN 'entregado'
    WHEN 'ENTREGADO CON NOVEDAD' THEN 'entregado_novedad'
    WHEN 'RECHAZADO POR CLIENTE' THEN 'rechazado'
    WHEN 'RECHAZADO' THEN 'rechazado'
    WHEN 'CANCELADO' THEN 'cancelado'
    ELSE 'sin_consolidar'
  END;
$$;

-- ------------------------------------------------------------
-- Helper: buscar cliente_id por empresa name
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _cliente_id_por_empresa(empresa_name text)
RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT id FROM clientes
   WHERE upper(trim(nombre)) = upper(trim(coalesce(empresa_name, '')))
   LIMIT 1;
$$;

-- ============================================================
-- fn_sync_viajes_batch
-- ============================================================
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

  c_insertados            int := 0;
  c_actualizados          int := 0;
  c_saltados_netfleet     int := 0;
  c_saltados_terminal     int := 0;
  c_marcados_cancelado    int := 0;
  c_errores               int := 0;
  err_samples             jsonb := '[]'::jsonb;
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
        -- Regla 1: Netfleet gana
        IF v_existing_fuente = 'netfleet' THEN
          c_saltados_netfleet := c_saltados_netfleet + 1;
          CONTINUE;
        END IF;
        -- Regla 2: estados terminales no se sobrescriben (ya ejecutado)
        IF v_existing_estado IN ('en_ruta','entregado','finalizado','cancelado') THEN
          c_saltados_terminal := c_saltados_terminal + 1;
          CONTINUE;
        END IF;
        -- Regla 3: si Sheet dice cancelado, propagar
        IF v_estado_norm = 'cancelado' THEN
          UPDATE viajes_consolidados
          SET estado = 'cancelado', estado_original = v_estado_orig
          WHERE id = v_existing_id;
          c_marcados_cancelado := c_marcados_cancelado + 1;
          CONTINUE;
        END IF;
        -- UPDATE campos desde Sheet
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
        -- INSERT nuevo viaje desde Sheet
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
      'saltados_terminal', c_saltados_terminal,
      'marcados_cancelado', c_marcados_cancelado,
      'errores', c_errores,
      'err_samples', err_samples,
      'total_input', jsonb_array_length(p_payload)
    ));

  RETURN jsonb_build_object(
    'insertados', c_insertados,
    'actualizados', c_actualizados,
    'saltados_netfleet', c_saltados_netfleet,
    'saltados_terminal', c_saltados_terminal,
    'marcados_cancelado', c_marcados_cancelado,
    'errores', c_errores,
    'err_samples', err_samples,
    'total_input', jsonb_array_length(p_payload)
  );
END;
$$;

-- ============================================================
-- fn_sync_pedidos_batch
-- ============================================================
CREATE OR REPLACE FUNCTION fn_sync_pedidos_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row             jsonb;
  v_pedido_ref      text;
  v_cliente_id      uuid;
  v_existing_id     uuid;
  v_existing_estado text;
  v_estado_norm     text;
  v_estado_orig     text;

  c_insertados         int := 0;
  c_actualizados       int := 0;
  c_saltados_terminal  int := 0;
  c_marcados_cancelado int := 0;
  c_errores            int := 0;
  err_samples          jsonb := '[]'::jsonb;
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
      v_pedido_ref := trim(v_row->>'pedido_ref');
      IF v_pedido_ref IS NULL OR v_pedido_ref = '' THEN CONTINUE; END IF;

      v_cliente_id := COALESCE(
        (v_row->>'cliente_id')::uuid,
        _cliente_id_por_empresa(v_row->>'empresa')
      );
      v_estado_orig := v_row->>'estado_sheet';
      v_estado_norm := _norm_estado_pedido(v_estado_orig);

      -- Buscar match más reciente por (cliente_id, pedido_ref), no terminal
      SELECT id, estado INTO v_existing_id, v_existing_estado
      FROM pedidos
      WHERE pedido_ref = v_pedido_ref
        AND (cliente_id = v_cliente_id OR v_cliente_id IS NULL OR cliente_id IS NULL)
      ORDER BY
        CASE WHEN estado IN ('entregado','entregado_novedad','rechazado','cancelado') THEN 1 ELSE 0 END,
        updated_at DESC
      LIMIT 1;

      IF v_existing_id IS NOT NULL THEN
        -- Estados terminales: no tocar
        IF v_existing_estado IN ('en_ruta','entregado','entregado_novedad','rechazado','cancelado') THEN
          c_saltados_terminal := c_saltados_terminal + 1;
          CONTINUE;
        END IF;
        -- Propagar cancelado desde Sheet
        IF v_estado_norm = 'cancelado' THEN
          UPDATE pedidos
          SET estado = 'cancelado', estado_original = v_estado_orig
          WHERE id = v_existing_id;
          c_marcados_cancelado := c_marcados_cancelado + 1;
          CONTINUE;
        END IF;
        -- UPDATE campos (sin tocar viaje_id, que lo gestiona control.html / linker)
        UPDATE pedidos SET
          cliente_id             = COALESCE(v_cliente_id, cliente_id),
          id_consecutivo         = COALESCE(v_row->>'id_consecutivo',         id_consecutivo),
          empresa                = COALESCE(_norm_empresa(v_row->>'empresa'), empresa),
          zona                   = COALESCE(v_row->>'zona',                   zona),
          origen                 = COALESCE(v_row->>'origen',                 origen),
          destino                = COALESCE(v_row->>'destino',                destino),
          motivo_viaje           = COALESCE(v_row->>'motivo_viaje',           motivo_viaje),
          prioridad              = COALESCE(v_row->>'prioridad',              prioridad),
          fecha_cargue           = COALESCE((v_row->>'fecha_cargue')::timestamptz, fecha_cargue),
          fecha_entrega          = COALESCE((v_row->>'fecha_entrega')::timestamptz, fecha_entrega),
          peso_kg                = COALESCE((v_row->>'peso_kg')::numeric,     peso_kg),
          tipo_mercancia         = COALESCE(v_row->>'tipo_mercancia',         tipo_mercancia),
          contenedores           = COALESCE((v_row->>'contenedores')::int,    contenedores),
          cajas                  = COALESCE((v_row->>'cajas')::int,           cajas),
          bidones                = COALESCE((v_row->>'bidones')::int,         bidones),
          canecas                = COALESCE((v_row->>'canecas')::int,         canecas),
          unidades_sueltas       = COALESCE((v_row->>'unidades_sueltas')::int, unidades_sueltas),
          valor_mercancia        = COALESCE((v_row->>'valor_mercancia')::numeric, valor_mercancia),
          valor_factura          = COALESCE((v_row->>'valor_factura')::numeric,  valor_factura),
          tipo_vehiculo          = COALESCE(v_row->>'tipo_vehiculo',          tipo_vehiculo),
          flete                  = COALESCE((v_row->>'flete')::numeric,       flete),
          standby                = COALESCE((v_row->>'standby')::numeric,     standby),
          candado                = COALESCE((v_row->>'candado')::numeric,     candado),
          escolta                = COALESCE((v_row->>'escolta')::numeric,     escolta),
          itr                    = COALESCE((v_row->>'itr')::numeric,         itr),
          cargue_descargue       = COALESCE(v_row->>'cargue_descargue',       cargue_descargue),
          cliente_nombre         = COALESCE(v_row->>'cliente_nombre',         cliente_nombre),
          contacto_nombre        = COALESCE(v_row->>'contacto_nombre',        contacto_nombre),
          contacto_tel           = COALESCE(v_row->>'contacto_tel',           contacto_tel),
          direccion              = COALESCE(v_row->>'direccion',              direccion),
          horario                = COALESCE(v_row->>'horario',                horario),
          llamar_antes           = COALESCE((v_row->>'llamar_antes')::boolean, llamar_antes),
          observaciones          = COALESCE(v_row->>'observaciones',          observaciones),
          vendedor               = COALESCE(v_row->>'vendedor',               vendedor),
          jefe_zona              = COALESCE(v_row->>'jefe_zona',              jefe_zona),
          coordinador            = COALESCE(v_row->>'coordinador',            coordinador),
          placa                  = COALESCE(v_row->>'placa',                  placa),
          proveedor              = COALESCE(v_row->>'proveedor',              proveedor),
          soporte_1              = COALESCE(v_row->>'soporte_1',              soporte_1),
          soporte_2              = COALESCE(v_row->>'soporte_2',              soporte_2),
          soporte_3              = COALESCE(v_row->>'soporte_3',              soporte_3),
          confirma_vehiculo      = COALESCE(v_row->>'confirma_vehiculo',      confirma_vehiculo),
          bodega_email           = COALESCE(v_row->>'bodega_email',           bodega_email),
          nro_factura_proveedor  = COALESCE(v_row->>'nro_factura_proveedor',  nro_factura_proveedor),
          estado_original        = v_estado_orig,
          raw_payload            = v_row::text
        WHERE id = v_existing_id;
        c_actualizados := c_actualizados + 1;
      ELSE
        -- INSERT nuevo pedido
        INSERT INTO pedidos (
          pedido_ref, id_consecutivo, cliente_id, empresa, zona, origen, destino, fuente,
          motivo_viaje, prioridad, fecha_cargue, fecha_entrega,
          peso_kg, tipo_mercancia, contenedores, cajas, bidones, canecas, unidades_sueltas,
          valor_mercancia, valor_factura, tipo_vehiculo,
          flete, standby, candado, escolta, itr, cargue_descargue,
          cliente_nombre, contacto_nombre, contacto_tel, direccion, horario, llamar_antes,
          observaciones, vendedor, jefe_zona, coordinador, placa, proveedor,
          soporte_1, soporte_2, soporte_3, confirma_vehiculo, bodega_email,
          nro_factura_proveedor,
          estado, estado_original, raw_payload
        ) VALUES (
          v_pedido_ref, v_row->>'id_consecutivo', v_cliente_id, _norm_empresa(v_row->>'empresa'), v_row->>'zona',
          COALESCE(v_row->>'origen', '—'), COALESCE(v_row->>'destino', '—'),
          'sheet',
          v_row->>'motivo_viaje', v_row->>'prioridad',
          (v_row->>'fecha_cargue')::timestamptz, (v_row->>'fecha_entrega')::timestamptz,
          (v_row->>'peso_kg')::numeric, v_row->>'tipo_mercancia',
          COALESCE((v_row->>'contenedores')::int, 0), COALESCE((v_row->>'cajas')::int, 0),
          COALESCE((v_row->>'bidones')::int, 0), COALESCE((v_row->>'canecas')::int, 0),
          COALESCE((v_row->>'unidades_sueltas')::int, 0),
          (v_row->>'valor_mercancia')::numeric, (v_row->>'valor_factura')::numeric,
          v_row->>'tipo_vehiculo',
          COALESCE((v_row->>'flete')::numeric, 0),
          COALESCE((v_row->>'standby')::numeric, 0),
          COALESCE((v_row->>'candado')::numeric, 0),
          COALESCE((v_row->>'escolta')::numeric, 0),
          COALESCE((v_row->>'itr')::numeric, 0),
          v_row->>'cargue_descargue',
          v_row->>'cliente_nombre', v_row->>'contacto_nombre', v_row->>'contacto_tel',
          v_row->>'direccion', v_row->>'horario',
          COALESCE((v_row->>'llamar_antes')::boolean, false),
          v_row->>'observaciones', v_row->>'vendedor', v_row->>'jefe_zona',
          v_row->>'coordinador', v_row->>'placa', v_row->>'proveedor',
          v_row->>'soporte_1', v_row->>'soporte_2', v_row->>'soporte_3',
          v_row->>'confirma_vehiculo', v_row->>'bodega_email',
          v_row->>'nro_factura_proveedor',
          v_estado_norm, v_estado_orig, v_row::text
        );
        c_insertados := c_insertados + 1;
      END IF;
    EXCEPTION WHEN others THEN
      c_errores := c_errores + 1;
      IF jsonb_array_length(err_samples) < 5 THEN
        err_samples := err_samples || jsonb_build_object(
          'pedido_ref', v_pedido_ref, 'error', SQLERRM
        );
      END IF;
    END;
  END LOOP;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'sync_pedidos', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'insertados', c_insertados,
      'actualizados', c_actualizados,
      'saltados_terminal', c_saltados_terminal,
      'marcados_cancelado', c_marcados_cancelado,
      'errores', c_errores,
      'err_samples', err_samples,
      'total_input', jsonb_array_length(p_payload)
    ));

  RETURN jsonb_build_object(
    'insertados', c_insertados,
    'actualizados', c_actualizados,
    'saltados_terminal', c_saltados_terminal,
    'marcados_cancelado', c_marcados_cancelado,
    'errores', c_errores,
    'err_samples', err_samples,
    'total_input', jsonb_array_length(p_payload)
  );
END;
$$;

COMMIT;

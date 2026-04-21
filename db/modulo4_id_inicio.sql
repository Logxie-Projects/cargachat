-- ============================================================
-- pedidos.id_inicio — llave estable de AppSheet
--
-- Problema histórico: fn_sync_pedidos_batch lookup por pedido_ref +
-- cliente_id. Si Bernardo edita pedido_ref en Base_inicio-def (ej.
-- "RM 67705" → "RM-67705"), el sync crea/actualiza la nueva ref y
-- deja la vieja huérfana en Netfleet.
--
-- Fix: usar el ID_Inicio de AppSheet (col A, hex tipo "c778c027")
-- como llave estable. Renames → UPDATE de la misma fila.
--
-- Cambios:
--   1. pedidos.id_inicio text + UNIQUE INDEX WHERE NOT NULL
--   2. fn_sync_pedidos_batch: lookup por id_inicio primero, fallback
--      a pedido_ref+cliente_id solo para legacy (id_inicio IS NULL)
--   3. fn_pedidos_cleanup_ghosts(): borra rows fuente='sheet' que
--      tras un sync siguen con id_inicio=NULL (= no matcheados por
--      ningún ID_Inicio del CSV → fueron renombrados/eliminados del
--      Sheet hace tiempo)
--
-- Idempotente.
-- ============================================================

BEGIN;

-- 1) Columna + index
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS id_inicio text;
CREATE UNIQUE INDEX IF NOT EXISTS idx_pedidos_id_inicio
  ON pedidos(id_inicio) WHERE id_inicio IS NOT NULL;

-- 2) Extender CHECK acciones_operador
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
    'asociar_viaje','desasociar_viaje',
    'cleanup_ghosts'
  ));

-- 3) fn_sync_pedidos_batch reescrita con lookup por id_inicio
CREATE OR REPLACE FUNCTION fn_sync_pedidos_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row             jsonb;
  v_id_inicio       text;
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
      v_id_inicio  := NULLIF(trim(v_row->>'id_inicio'), '');
      v_pedido_ref := trim(v_row->>'pedido_ref');
      IF v_pedido_ref IS NULL OR v_pedido_ref = '' THEN CONTINUE; END IF;

      v_cliente_id := COALESCE(
        (v_row->>'cliente_id')::uuid,
        _cliente_id_por_empresa(v_row->>'empresa')
      );
      v_estado_orig := v_row->>'estado_sheet';
      v_estado_norm := _norm_estado_pedido(v_estado_orig);

      v_existing_id := NULL;
      v_existing_estado := NULL;

      -- Lookup primario: id_inicio (estable, sobrevive renames)
      IF v_id_inicio IS NOT NULL THEN
        SELECT id, estado INTO v_existing_id, v_existing_estado
          FROM pedidos WHERE id_inicio = v_id_inicio LIMIT 1;
      END IF;

      -- Fallback legacy: pedido_ref + cliente, solo entre rows sin id_inicio
      IF v_existing_id IS NULL THEN
        SELECT id, estado INTO v_existing_id, v_existing_estado
        FROM pedidos
        WHERE pedido_ref = v_pedido_ref
          AND id_inicio IS NULL
          AND (cliente_id = v_cliente_id OR v_cliente_id IS NULL OR cliente_id IS NULL)
        ORDER BY
          CASE WHEN estado IN ('entregado','entregado_novedad','rechazado','cancelado') THEN 1 ELSE 0 END,
          updated_at DESC
        LIMIT 1;
      END IF;

      IF v_existing_id IS NOT NULL THEN
        IF v_existing_estado IN ('en_ruta','entregado','entregado_novedad','rechazado','cancelado') THEN
          c_saltados_terminal := c_saltados_terminal + 1;
          CONTINUE;
        END IF;
        IF v_estado_norm = 'cancelado' THEN
          UPDATE pedidos
          SET estado = 'cancelado', estado_original = v_estado_orig,
              id_inicio = COALESCE(v_id_inicio, id_inicio)
          WHERE id = v_existing_id;
          c_marcados_cancelado := c_marcados_cancelado + 1;
          CONTINUE;
        END IF;
        UPDATE pedidos SET
          id_inicio              = COALESCE(v_id_inicio, id_inicio),
          pedido_ref             = v_pedido_ref,  -- propagar rename
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
        INSERT INTO pedidos (
          id_inicio, pedido_ref, id_consecutivo, cliente_id, empresa, zona, origen, destino, fuente,
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
          v_id_inicio, v_pedido_ref, v_row->>'id_consecutivo', v_cliente_id, _norm_empresa(v_row->>'empresa'), v_row->>'zona',
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
          'pedido_ref', v_pedido_ref, 'id_inicio', v_id_inicio, 'error', SQLERRM
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

-- 4) fn_pedidos_cleanup_ghosts
--    Borra pedidos fuente='sheet' que después de un sync siguen sin
--    id_inicio. Esos son rows que el CSV actual no matcheó por ningún
--    lado → renombrados o eliminados del Sheet hace tiempo.
--    Skip los que tienen viaje_id (consolidados — no romper relación).
CREATE OR REPLACE FUNCTION fn_pedidos_cleanup_ghosts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_borrados int;
  v_samples  jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede limpiar huérfanos';
  END IF;

  -- Snapshot antes de borrar
  SELECT jsonb_agg(jsonb_build_object('pedido_ref', pedido_ref, 'estado', estado, 'fecha', fecha_cargue))
    INTO v_samples
  FROM (
    SELECT pedido_ref, estado, fecha_cargue
    FROM pedidos
    WHERE fuente = 'sheet'
      AND id_inicio IS NULL
      AND viaje_id IS NULL  -- no romper relaciones
      AND estado IN ('sin_consolidar','consolidado','cancelado')
    LIMIT 20
  ) t;

  DELETE FROM pedidos
  WHERE fuente = 'sheet'
    AND id_inicio IS NULL
    AND viaje_id IS NULL
    AND estado IN ('sin_consolidar','consolidado','cancelado');
  GET DIAGNOSTICS c_borrados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cleanup_ghosts', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object('borrados', c_borrados, 'samples', v_samples));

  RETURN jsonb_build_object('borrados', c_borrados, 'samples', v_samples);
END;
$$;

COMMIT;

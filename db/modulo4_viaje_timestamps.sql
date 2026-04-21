-- ============================================================
-- Módulo 4 — Timestamps tracking a nivel viaje + auto-derivación de estado
--
-- El Sheet Seguimiento tiene columnas per-pedido pero los timestamps
-- de cargue/descargue son iguales para todos los pedidos del mismo
-- viaje (es el mismo carro). Los capturamos al nivel viaje.
--
-- Regla de auto-estado para viajes:
--   - TODOS los pedidos en terminal (entregado/rechazado/devuelto/cancelado)
--     → viaje = 'entregado' (cierra ciclo, operador decide si finaliza)
--   - salida_cargue IS NOT NULL y no todos terminales → viaje = 'en_ruta'
--   - Else → mantiene el estado actual (confirmado/pendiente/etc)
-- ============================================================

BEGIN;

-- 1) Columnas nuevas en viajes_consolidados
ALTER TABLE viajes_consolidados
  ADD COLUMN IF NOT EXISTS llegada_cargue     timestamptz,
  ADD COLUMN IF NOT EXISTS salida_cargue      timestamptz,
  ADD COLUMN IF NOT EXISTS llegada_descargue  timestamptz,
  ADD COLUMN IF NOT EXISTS salida_descargue   timestamptz;

-- 2) fn_recalc_viaje_estado_desde_pedidos
--    Aplica las reglas de derivación. No toca viajes ya finalizados/cancelados.
CREATE OR REPLACE FUNCTION fn_recalc_viaje_estado_desde_pedidos(p_viaje_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_estado_actual  text;
  v_salida_cargue  timestamptz;
  v_total          int;
  v_terminales     int;
  v_entregados     int;
  v_nuevo_estado   text;
BEGIN
  SELECT estado, salida_cargue INTO v_estado_actual, v_salida_cargue
    FROM viajes_consolidados WHERE id = p_viaje_id;

  IF v_estado_actual IS NULL THEN RETURN NULL; END IF;

  -- No reescribir estados terminales operativos del viaje
  IF v_estado_actual IN ('finalizado','cancelado') THEN RETURN v_estado_actual; END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE estado IN ('entregado','entregado_novedad','rechazado','devuelto_bodega','cancelado')),
    COUNT(*) FILTER (WHERE estado IN ('entregado','entregado_novedad'))
    INTO v_total, v_terminales, v_entregados
    FROM pedidos WHERE viaje_id = p_viaje_id;

  IF v_total = 0 THEN RETURN v_estado_actual; END IF;

  -- Todos los pedidos en terminal y al menos 1 entregado → viaje = entregado
  -- (si ninguno entregado, no tocamos — state machine de viaje no tiene 'rechazado')
  IF v_terminales = v_total AND v_entregados > 0 THEN
    v_nuevo_estado := 'entregado';
  -- Hay timestamp de salida de cargue → carro arrancó
  ELSIF v_salida_cargue IS NOT NULL THEN
    v_nuevo_estado := 'en_ruta';
  -- Por default mantiene
  ELSE
    v_nuevo_estado := v_estado_actual;
  END IF;

  IF v_nuevo_estado IS DISTINCT FROM v_estado_actual THEN
    UPDATE viajes_consolidados SET estado = v_nuevo_estado WHERE id = p_viaje_id;
  END IF;

  RETURN v_nuevo_estado;
END;
$$;

-- 3) Trigger en pedidos: al cambiar estado del pedido → recalcular su viaje
CREATE OR REPLACE FUNCTION _trg_pedido_recalc_viaje()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.viaje_id IS NOT NULL AND (OLD.estado IS DISTINCT FROM NEW.estado OR OLD.viaje_id IS DISTINCT FROM NEW.viaje_id) THEN
    PERFORM fn_recalc_viaje_estado_desde_pedidos(NEW.viaje_id);
  END IF;
  -- Si el viaje anterior era distinto, también recalcularlo
  IF OLD.viaje_id IS NOT NULL AND OLD.viaje_id IS DISTINCT FROM NEW.viaje_id THEN
    PERFORM fn_recalc_viaje_estado_desde_pedidos(OLD.viaje_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pedido_recalc_viaje ON pedidos;
CREATE TRIGGER trg_pedido_recalc_viaje
  AFTER UPDATE OF estado, viaje_id ON pedidos
  FOR EACH ROW EXECUTE FUNCTION _trg_pedido_recalc_viaje();

-- 4) fn_sync_pedidos_seguimiento_batch — actualizar para capturar timestamps del viaje
--    Cada row del Sheet tiene LLEGADA A CARGUE, SALIDA DE CARGUE, etc. Como todos
--    los pedidos del mismo viaje comparten estos timestamps, UPDATE es idempotente.
CREATE OR REPLACE FUNCTION fn_sync_pedidos_seguimiento_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row        jsonb;
  v_id_inicio  text;
  v_pedido_id  uuid;
  v_viaje_id   uuid;
  v_seg_est    text;
  v_exitoso    boolean;
  v_num        int;
  v_fecha      timestamptz;
  v_coment     text;
  v_novedad    text;
  v_foto       text;
  v_max_ok     int;

  v_lc timestamptz; v_sc timestamptz; v_ld timestamptz; v_sd timestamptz;

  c_intentos_ins  int := 0;
  c_pedidos_touch int := 0;
  c_viajes_touch  int := 0;
  c_no_match      int := 0;
  c_errores       int := 0;
  err_samples     jsonb := '[]'::jsonb;
  v_viajes_tocados uuid[] := ARRAY[]::uuid[];
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede disparar sync seguimiento';
  END IF;

  IF jsonb_typeof(p_payload) <> 'array' THEN
    RAISE EXCEPTION 'payload debe ser un array JSON';
  END IF;

  FOR v_row IN SELECT jsonb_array_elements(p_payload) LOOP
    BEGIN
      v_id_inicio := NULLIF(trim(v_row->>'id_inicio'), '');
      IF v_id_inicio IS NULL THEN CONTINUE; END IF;

      SELECT id, viaje_id INTO v_pedido_id, v_viaje_id
        FROM pedidos WHERE id_inicio = v_id_inicio LIMIT 1;
      IF v_pedido_id IS NULL THEN
        c_no_match := c_no_match + 1;
        CONTINUE;
      END IF;

      v_seg_est := upper(trim(coalesce(v_row->>'seguimiento_estado', '')));
      v_foto    := NULLIF(trim(coalesce(v_row->>'foto_cumplido', '')), '');
      v_exitoso := v_seg_est IN ('ENTREGADO OK','ENTREGADO CON NOVEDAD');

      -- Propagación directa del estado desde Sheet
      IF v_seg_est = 'ENTREGADO OK' THEN
        UPDATE pedidos SET estado = 'entregado'
          WHERE id = v_pedido_id AND estado <> 'entregado';
        c_pedidos_touch := c_pedidos_touch + 1;
      ELSIF v_seg_est = 'ENTREGADO CON NOVEDAD' THEN
        UPDATE pedidos SET estado = 'entregado_novedad'
          WHERE id = v_pedido_id AND estado <> 'entregado_novedad';
        c_pedidos_touch := c_pedidos_touch + 1;
      ELSIF v_seg_est = 'RECHAZADO POR CLIENTE' THEN
        UPDATE pedidos SET estado = 'rechazado'
          WHERE id = v_pedido_id
            AND estado NOT IN ('entregado','entregado_novedad','devuelto_bodega','cancelado');
      ELSIF v_seg_est = 'PENDIENTE' THEN
        UPDATE pedidos SET estado = 'en_ruta'
          WHERE id = v_pedido_id AND estado IN ('consolidado','asignado');
      END IF;

      -- Capturar timestamps de cargue/descargue al nivel viaje
      IF v_viaje_id IS NOT NULL THEN
        v_lc := NULLIF(trim(coalesce(v_row->>'llegada_cargue', '')), '')::timestamptz;
        v_sc := NULLIF(trim(coalesce(v_row->>'salida_cargue', '')), '')::timestamptz;
        v_ld := NULLIF(trim(coalesce(v_row->>'llegada_descargue', '')), '')::timestamptz;
        v_sd := NULLIF(trim(coalesce(v_row->>'salida_descargue', '')), '')::timestamptz;

        IF v_lc IS NOT NULL OR v_sc IS NOT NULL OR v_ld IS NOT NULL OR v_sd IS NOT NULL THEN
          UPDATE viajes_consolidados SET
            llegada_cargue    = COALESCE(v_lc, llegada_cargue),
            salida_cargue     = COALESCE(v_sc, salida_cargue),
            llegada_descargue = COALESCE(v_ld, llegada_descargue),
            salida_descargue  = COALESCE(v_sd, salida_descargue)
          WHERE id = v_viaje_id;
          IF NOT (v_viaje_id = ANY(v_viajes_tocados)) THEN
            v_viajes_tocados := array_append(v_viajes_tocados, v_viaje_id);
          END IF;
        END IF;
      END IF;

      -- Detectar max intento con datos
      v_max_ok := 0;
      FOR v_num IN 1..3 LOOP
        IF NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_fecha'), '')), '') IS NOT NULL
           OR NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_comentario'), '')), '') IS NOT NULL
           OR (v_num = 1 AND (v_foto IS NOT NULL
               OR NULLIF(trim(coalesce(v_row->>'intento_1_novedad', '')), '') IS NOT NULL))
        THEN v_max_ok := v_num;
        END IF;
      END LOOP;

      IF v_max_ok = 0 AND v_seg_est IN ('ENTREGADO OK','ENTREGADO CON NOVEDAD','RECHAZADO POR CLIENTE')
      THEN v_max_ok := 1; END IF;

      IF v_max_ok = 0 THEN CONTINUE; END IF;

      FOR v_num IN 1..v_max_ok LOOP
        v_fecha  := NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_fecha'), '')), '')::timestamptz;
        v_coment := NULLIF(trim(coalesce(v_row->>('intento_'||v_num||'_comentario'), '')), '');
        v_novedad := CASE
          WHEN v_num = 1 THEN NULLIF(trim(coalesce(v_row->>'intento_1_novedad', '')), '')
          ELSE NULL
        END;

        INSERT INTO intentos_entrega (
          pedido_id, intento_num, fecha, exitoso,
          novedad, comentario, foto_url, fuente
        ) VALUES (
          v_pedido_id, v_num, v_fecha,
          (v_num = v_max_ok AND v_exitoso),
          v_novedad, v_coment,
          CASE WHEN v_num = v_max_ok THEN v_foto ELSE NULL END,
          'sheet'
        )
        ON CONFLICT (pedido_id, intento_num) DO UPDATE
        SET fecha       = COALESCE(EXCLUDED.fecha,      intentos_entrega.fecha),
            exitoso     = EXCLUDED.exitoso,
            novedad     = COALESCE(EXCLUDED.novedad,    intentos_entrega.novedad),
            comentario  = COALESCE(EXCLUDED.comentario, intentos_entrega.comentario),
            foto_url    = COALESCE(EXCLUDED.foto_url,   intentos_entrega.foto_url),
            updated_at  = now();

        IF FOUND THEN c_intentos_ins := c_intentos_ins + 1; END IF;
      END LOOP;
    EXCEPTION WHEN others THEN
      c_errores := c_errores + 1;
      IF jsonb_array_length(err_samples) < 5 THEN
        err_samples := err_samples || jsonb_build_object(
          'id_inicio', v_id_inicio, 'error', SQLERRM
        );
      END IF;
    END;
  END LOOP;

  -- Recalcular estado de los viajes tocados (aplica las reglas cargue/terminal)
  IF array_length(v_viajes_tocados, 1) > 0 THEN
    FOR v_viaje_id IN SELECT unnest(v_viajes_tocados) LOOP
      PERFORM fn_recalc_viaje_estado_desde_pedidos(v_viaje_id);
      c_viajes_touch := c_viajes_touch + 1;
    END LOOP;
  END IF;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'sync_seguimiento', 'pedido',
    '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'intentos_touched', c_intentos_ins,
      'pedidos_touched',  c_pedidos_touch,
      'viajes_touched',   c_viajes_touch,
      'no_match',         c_no_match,
      'errores',          c_errores,
      'err_samples',      err_samples,
      'total_input',      jsonb_array_length(p_payload)
    ));

  RETURN jsonb_build_object(
    'intentos_touched', c_intentos_ins,
    'pedidos_touched',  c_pedidos_touch,
    'viajes_touched',   c_viajes_touch,
    'no_match',         c_no_match,
    'errores',          c_errores,
    'err_samples',      err_samples,
    'total_input',      jsonb_array_length(p_payload)
  );
END;
$$;

-- 5) Backfill one-shot: recalcular todos los viajes activos (aplicar reglas a data existente)
DO $$
DECLARE vid uuid;
BEGIN
  FOR vid IN SELECT id FROM viajes_consolidados WHERE estado IN ('pendiente','confirmado','en_ruta')
  LOOP
    PERFORM fn_recalc_viaje_estado_desde_pedidos(vid);
  END LOOP;
END $$;

COMMIT;

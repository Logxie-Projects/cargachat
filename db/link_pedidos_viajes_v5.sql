-- ═══════════════════════════════════════════════════════════════
-- LINKER v5 — re-linkeo de pedidos reconsolidados
--
-- Caso: pedido que viaja primero en viaje A, A se cancela, y después
-- el pedido se reconsolida en viaje B (no cancelado). El linker v3/v4
-- deja el pedido apuntando a A (cancelado) porque solo tocan pedidos
-- con viaje_id NULL. v5 captura este caso post-linkeo.
--
-- Síntoma operativo (reportado por Bernardo 2026-04-22):
--   "RM-73281 destino TENJO en el viaje RT-TOTAL-1776820776627 no
--    fue identificado por el analizador de ruta"
-- El analizador hace SELECT ... WHERE viaje_id IN (viajes activos).
-- Si el viaje_id del pedido apunta a un cancelado, el analizador
-- no lo ve aunque el operador sepa que "pertenece" al viaje nuevo.
--
-- Regla (conservadora, solo mueve cuando el actual está cancelado):
--   1. Pedido está en estado != 'cancelado' (pedido activo)
--   2. Su viaje actual está en estado 'cancelado'
--   3. Existe ≥1 viaje no-cancelado cuyo consecutivos/PEDIDOS_INCLUIDOS
--      lista al pedido_ref (substring, ≥5 chars)
--   4. Elegir el más reciente no-cancelado (desempate por cliente match)
--
-- NO toca:
--   - Pedidos en estado cancelado (aunque el viaje esté cancelado,
--     es el estado correcto de ambos)
--   - Casos donde ambos viajes (actual y candidato) están activos —
--     eso es ambiguo y lo dejamos al operador
--
-- Idempotente: si un pedido ya se relinqueó, re-correr no hace nada.
-- ═══════════════════════════════════════════════════════════════

-- Función standalone por si se necesita correr v5 independientemente.
CREATE OR REPLACE FUNCTION fn_link_v5_relink_reconsolidados()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  c_relinkeados int;
  samples jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff, service_role o postgres pueden correr linker v5';
  END IF;

  -- CTE con candidatos: pedidos activos en viajes cancelados que aparecen en otro viaje no-cancelado
  WITH candidates AS (
    SELECT
      p.id                   AS pedido_id,
      p.pedido_ref,
      p.viaje_id             AS viaje_actual,
      v_mejor.id             AS viaje_mejor,
      v_mejor.viaje_ref      AS ref_mejor,
      v_mejor.created_at     AS created_mejor,
      CASE WHEN v_mejor.cliente_id = p.cliente_id THEN 1 ELSE 2 END AS prefer_cliente
    FROM pedidos p
    JOIN viajes_consolidados v_actual ON p.viaje_id = v_actual.id
    JOIN viajes_consolidados v_mejor
      ON v_mejor.id <> v_actual.id
     AND v_mejor.estado <> 'cancelado'
     AND COALESCE(
           safe_json_get(v_mejor.raw_payload, 'PEDIDOS_INCLUIDOS'),
           v_mejor.consecutivos
         ) ILIKE '%' || p.pedido_ref || '%'
    WHERE p.pedido_ref IS NOT NULL
      AND length(p.pedido_ref) >= 5
      AND p.estado <> 'cancelado'
      AND v_actual.estado = 'cancelado'
  ),
  best AS (
    SELECT DISTINCT ON (pedido_id)
      pedido_id, viaje_mejor, ref_mejor, viaje_actual
    FROM candidates
    ORDER BY pedido_id, prefer_cliente, created_mejor DESC
  ),
  updated AS (
    UPDATE pedidos p
    SET viaje_id = b.viaje_mejor
    FROM best b
    WHERE p.id = b.pedido_id
    RETURNING p.id, p.pedido_ref, b.ref_mejor
  )
  SELECT COUNT(*)::int,
         COALESCE(jsonb_agg(jsonb_build_object('ref', pedido_ref, 'viaje', ref_mejor))
                  FILTER (WHERE pedido_ref IS NOT NULL), '[]'::jsonb)
    INTO c_relinkeados, samples
    FROM updated;

  -- Audit — una entry de resumen
  IF c_relinkeados > 0 THEN
    INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'run_linkers', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
      jsonb_build_object(
        'pase',          'v5_reconsolidacion',
        'relinkeados',   c_relinkeados,
        'samples',       CASE WHEN jsonb_array_length(samples) <= 20 THEN samples
                              ELSE (SELECT jsonb_agg(e) FROM jsonb_array_elements(samples) e LIMIT 20) END
      ));
  END IF;

  RETURN jsonb_build_object(
    'relinkeados_v5', c_relinkeados,
    'samples',        samples
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- Redefinir fn_run_linkers() para encadenar v3 + v4 + v5
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_run_linkers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  c_antes         int;
  c_mid           int;
  c_despues       int;
  c_linkeados_v3  int;
  c_linkeados_v4  int;
  c_linkeados_v5  int;
  c_total         int;
  v5_result       jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff, service_role o postgres pueden correr linkers';
  END IF;

  SELECT COUNT(*) INTO c_antes FROM pedidos WHERE viaje_id IS NULL;
  SELECT COUNT(*) INTO c_total FROM pedidos;

  -- ═══ PASE 1: v3 regex parser (aliases intra-token) ═══
  WITH viaje_refs AS (
    SELECT
      v.id         AS viaje_id,
      v.cliente_id AS cliente_id,
      v.created_at,
      unnest(
        expand_consecutivos_v3(
          COALESCE(safe_json_get(v.raw_payload, 'PEDIDOS_INCLUIDOS'), v.consecutivos)
        )
      ) AS canon_ref
    FROM viajes_consolidados v
  ),
  matches AS (
    SELECT DISTINCT ON (p.id)
      p.id        AS pedido_id,
      vr.viaje_id AS viaje_id_nuevo
    FROM pedidos p
    JOIN viaje_refs vr
      ON canonicalize_pedido_ref(p.pedido_ref) = vr.canon_ref
    WHERE p.viaje_id IS NULL
      AND p.pedido_ref IS NOT NULL
    ORDER BY p.id,
      CASE WHEN vr.cliente_id = p.cliente_id THEN 1
           WHEN vr.cliente_id IS NULL            THEN 2
           ELSE 3 END,
      vr.created_at DESC
  )
  UPDATE pedidos p
  SET viaje_id = m.viaje_id_nuevo,
      estado   = CASE WHEN p.estado = 'sin_consolidar' THEN 'consolidado' ELSE p.estado END
  FROM matches m
  WHERE m.pedido_id = p.id;

  SELECT COUNT(*) INTO c_mid FROM pedidos WHERE viaje_id IS NULL;
  c_linkeados_v3 := c_antes - c_mid;

  -- ═══ PASE 2: v4 substring (BUSCARX-style) ═══
  WITH candidates AS (
    SELECT
      p.id         AS pedido_id,
      v.id         AS viaje_id,
      v.cliente_id AS viaje_cliente_id,
      p.cliente_id AS pedido_cliente_id,
      v.created_at,
      CASE WHEN v.cliente_id = p.cliente_id THEN 1 ELSE 2 END AS prefer
    FROM pedidos p
    JOIN viajes_consolidados v
      ON COALESCE(safe_json_get(v.raw_payload, 'PEDIDOS_INCLUIDOS'), v.consecutivos)
         ILIKE '%' || p.pedido_ref || '%'
    WHERE p.viaje_id IS NULL
      AND p.pedido_ref IS NOT NULL
      AND length(p.pedido_ref) >= 5
  ),
  unique_matches AS (
    SELECT pedido_id,
           (array_agg(viaje_id ORDER BY prefer, created_at DESC))[1] AS viaje_id_nuevo,
           COUNT(*) AS n_matches
    FROM candidates
    GROUP BY pedido_id
    HAVING COUNT(*) = 1
        OR COUNT(*) FILTER (WHERE prefer = 1) = 1
  )
  UPDATE pedidos p
  SET viaje_id = um.viaje_id_nuevo,
      estado   = CASE WHEN p.estado = 'sin_consolidar' THEN 'consolidado' ELSE p.estado END
  FROM unique_matches um
  WHERE p.id = um.pedido_id;

  SELECT COUNT(*) INTO c_despues FROM pedidos WHERE viaje_id IS NULL;
  c_linkeados_v4 := c_mid - c_despues;

  -- ═══ PASE 3: v5 reconsolidación (pedidos activos en viajes cancelados) ═══
  v5_result := fn_link_v5_relink_reconsolidados();
  c_linkeados_v5 := (v5_result->>'relinkeados_v5')::int;

  -- Audit — entrada de resumen
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'run_linkers', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'huerfanos_antes',   c_antes,
      'linkeados_v3',      c_linkeados_v3,
      'linkeados_v4',      c_linkeados_v4,
      'linkeados_v5',      c_linkeados_v5,
      'huerfanos_despues', c_despues,
      'total_pedidos',     c_total
    ));

  RETURN jsonb_build_object(
    'huerfanos_antes',   c_antes,
    'linkeados_v3',      c_linkeados_v3,
    'linkeados_v4',      c_linkeados_v4,
    'linkeados_v5',      c_linkeados_v5,
    'huerfanos_despues', c_despues,
    'total_pedidos',     c_total,
    'pct_linked',        ROUND(100.0 * (c_total - c_despues) / NULLIF(c_total, 0), 1)
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- Smoke: correr el pase v5 ahora y reportar qué arregló
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE res jsonb;
BEGIN
  res := fn_link_v5_relink_reconsolidados();
  RAISE NOTICE 'v5 re-linkeo ejecutado: relinkeados=% · samples=%',
    res->>'relinkeados_v5', res->'samples';
END $$;

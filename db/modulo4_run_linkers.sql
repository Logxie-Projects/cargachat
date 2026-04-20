-- ============================================================
-- MÓDULO 4 — fn_run_linkers()
--
-- Wrapper RPC que corre los dos pases de linker en secuencia:
--   1. v3 regex parser (aliases de pedido dentro del mismo token)
--   2. v4 substring BUSCARX-style (guardrails: ref ≥5 chars + match único)
--
-- Se invoca desde control.html al final del botón 🔄 Sync.
-- Idempotente: solo toca pedidos con viaje_id IS NULL.
--
-- Precondiciones:
--   - expand_consecutivos_v3() instalado (db/link_pedidos_viajes_v3.sql)
--   - safe_json_get() y canonicalize_pedido_ref() instalados
--
-- Returns jsonb:
--   {huerfanos_antes, linkeados_v3, linkeados_v4, huerfanos_despues,
--    total_pedidos, pct_linked}
-- ============================================================

BEGIN;

-- Extender CHECK de acciones_operador con 'run_linkers'
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

CREATE OR REPLACE FUNCTION fn_run_linkers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_antes         int;
  c_mid           int;
  c_despues       int;
  c_linkeados_v3  int;
  c_linkeados_v4  int;
  c_total         int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff, service_role o postgres pueden correr linkers';
  END IF;

  SELECT COUNT(*) INTO c_antes   FROM pedidos WHERE viaje_id IS NULL;
  SELECT COUNT(*) INTO c_total   FROM pedidos;

  -- ═══ PASE 1: v3 regex parser (aliases intra-token) ═══
  WITH viaje_refs AS (
    SELECT
      v.id         AS viaje_id,
      v.cliente_id AS cliente_id,
      v.created_at,
      unnest(
        expand_consecutivos_v3(
          COALESCE(
            safe_json_get(v.raw_payload, 'PEDIDOS_INCLUIDOS'),
            v.consecutivos
          )
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
     AND (vr.cliente_id = p.cliente_id OR vr.cliente_id IS NULL)
    WHERE p.viaje_id IS NULL
      AND p.pedido_ref IS NOT NULL
    ORDER BY p.id,
      CASE WHEN vr.cliente_id = p.cliente_id THEN 1 ELSE 2 END,
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
      AND (v.cliente_id = p.cliente_id OR v.cliente_id IS NULL OR p.cliente_id IS NULL)
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

  -- Audit
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'run_linkers', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'huerfanos_antes',   c_antes,
      'linkeados_v3',      c_linkeados_v3,
      'linkeados_v4',      c_linkeados_v4,
      'huerfanos_despues', c_despues,
      'total_pedidos',     c_total
    ));

  RETURN jsonb_build_object(
    'huerfanos_antes',   c_antes,
    'linkeados_v3',      c_linkeados_v3,
    'linkeados_v4',      c_linkeados_v4,
    'huerfanos_despues', c_despues,
    'total_pedidos',     c_total,
    'pct_linked',        ROUND(100.0 * (c_total - c_despues) / NULLIF(c_total, 0), 1)
  );
END;
$$;

COMMIT;

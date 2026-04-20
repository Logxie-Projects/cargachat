-- ============================================================
-- Linker v4: segundo pase tipo BUSCARX (substring matching)
--
-- Replica la fórmula de Bernardo en Google Sheets:
--   =BUSCARX("*"&C2:C&"*"; ASIGNADOS!$C$2:$C; ASIGNADOS!$A$2:$A; ...)
--
-- Lógica: busca si el pedido_ref aparece como SUBSTRING dentro del
-- PEDIDOS_INCLUIDOS (o consecutivos) de algún viaje. Si sí, asigna
-- ese viaje_id al pedido.
--
-- Este pase corre DESPUÉS del v3 (parser regex) sobre los pedidos
-- que siguen huérfanos. Complementa sin reemplazar.
--
-- Guardrails (evitar falsos positivos):
--   1. Solo refs de ≥5 caracteres (evita "RM-6" matcheando RM-60/600/6000)
--   2. Solo si encuentra EXACTAMENTE 1 viaje que contiene el ref
--      (si hay múltiples, ambiguo → skip, que humano decida)
--   3. Match preferente por cliente_id compatible si hay elección
--
-- Idempotente. Solo toca pedidos con viaje_id IS NULL.
-- ============================================================

BEGIN;

-- Contador antes
DO $$
DECLARE n int;
BEGIN
  SELECT COUNT(*) INTO n FROM pedidos WHERE viaje_id IS NULL;
  RAISE NOTICE 'Huérfanos antes del pase 2: %', n;
END $$;

-- Pase 2: substring match con guardrails
WITH candidates AS (
  SELECT
    p.id AS pedido_id,
    v.id AS viaje_id,
    v.cliente_id AS viaje_cliente_id,
    p.cliente_id AS pedido_cliente_id,
    v.created_at,
    -- preferencia: cliente match > no match
    CASE WHEN v.cliente_id = p.cliente_id THEN 1 ELSE 2 END AS prefer
  FROM pedidos p
  JOIN viajes_consolidados v
    ON COALESCE(safe_json_get(v.raw_payload, 'PEDIDOS_INCLUIDOS'), v.consecutivos)
       ILIKE '%' || p.pedido_ref || '%'
  WHERE p.viaje_id IS NULL
    AND p.pedido_ref IS NOT NULL
    AND length(p.pedido_ref) >= 5     -- guardrail 1: refs suficientemente únicos
    AND (v.cliente_id = p.cliente_id OR v.cliente_id IS NULL OR p.cliente_id IS NULL)
),
unique_matches AS (
  -- Solo pedidos con EXACTAMENTE 1 viaje preferido (o 1 total si no hay preferido)
  SELECT pedido_id, (array_agg(viaje_id ORDER BY prefer, created_at DESC))[1] AS viaje_id_nuevo,
         COUNT(*) AS n_matches
  FROM candidates
  GROUP BY pedido_id
  HAVING COUNT(*) = 1                 -- guardrail 2: solo matches únicos
      OR COUNT(*) FILTER (WHERE prefer = 1) = 1  -- o un único match por cliente
)
UPDATE pedidos p
SET viaje_id = um.viaje_id_nuevo,
    estado = CASE WHEN p.estado = 'sin_consolidar' THEN 'consolidado' ELSE p.estado END
FROM unique_matches um
WHERE p.id = um.pedido_id;

-- Contador después
DO $$
DECLARE n int;
BEGIN
  SELECT COUNT(*) INTO n FROM pedidos WHERE viaje_id IS NULL;
  RAISE NOTICE 'Huérfanos después del pase 2: %', n;
END $$;

COMMIT;

-- Reporte
SELECT
  'linkeados' AS m, COUNT(*) AS n FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'huérfanos', COUNT(*) FROM pedidos WHERE viaje_id IS NULL
UNION ALL SELECT 'total', COUNT(*) FROM pedidos;

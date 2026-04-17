-- ============================================================
-- Diagnóstico de pedido_ref duplicados en pedidos
-- ============================================================

-- Total de dupes: cuántos pedido_ref distintos aparecen >1 vez
SELECT
  'pedido_refs únicos totales' AS metrica,
  COUNT(DISTINCT pedido_ref) AS n
FROM pedidos WHERE pedido_ref IS NOT NULL
UNION ALL
SELECT 'pedido_refs duplicados (aparecen >1 vez)',
       COUNT(*)
FROM (
  SELECT pedido_ref FROM pedidos
  WHERE pedido_ref IS NOT NULL
  GROUP BY pedido_ref HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'filas totales involucradas en dupes',
       COUNT(*)
FROM pedidos
WHERE pedido_ref IN (
  SELECT pedido_ref FROM pedidos
  WHERE pedido_ref IS NOT NULL
  GROUP BY pedido_ref HAVING COUNT(*) > 1
);

-- Top 10 dupes con más apariciones
SELECT pedido_ref, COUNT(*) AS apariciones
FROM pedidos
WHERE pedido_ref IS NOT NULL
GROUP BY pedido_ref
HAVING COUNT(*) > 1
ORDER BY apariciones DESC, pedido_ref
LIMIT 10;

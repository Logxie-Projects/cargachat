SELECT
  COUNT(*) FILTER (WHERE viaje_id IS NOT NULL) AS linkeados,
  COUNT(*) FILTER (WHERE viaje_id IS NULL) AS huerfanos,
  COUNT(*) AS total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE viaje_id IS NOT NULL) / COUNT(*), 1) AS pct
FROM pedidos;

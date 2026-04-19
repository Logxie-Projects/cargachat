SELECT
  COUNT(*) FILTER (WHERE revisado_at IS NULL AND estado='sin_consolidar') AS nuevos,
  COUNT(*) FILTER (WHERE revisado_at IS NOT NULL AND estado='sin_consolidar') AS revisados_pend,
  COUNT(*) FILTER (WHERE estado='consolidado') AS consolidado,
  COUNT(*) FILTER (WHERE estado='asignado')    AS asignado,
  COUNT(*) AS total
FROM pedidos;

SELECT 'viajes'     AS tbl, COUNT(*) AS n FROM viajes_consolidados
UNION ALL SELECT 'pedidos',       COUNT(*) FROM pedidos
UNION ALL SELECT 'pedidos linked',COUNT(*) FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'pedidos huérf', COUNT(*) FROM pedidos WHERE viaje_id IS NULL;

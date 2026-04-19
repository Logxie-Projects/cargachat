SELECT 'pedidos linkeados a viaje'   AS metric, COUNT(*) AS n FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'pedidos huérfanos',         COUNT(*)         FROM pedidos WHERE viaje_id IS NULL
UNION ALL SELECT 'viajes con >=1 pedido',     COUNT(DISTINCT viaje_id) FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'viajes vacíos (sin peds)',  COUNT(*)         FROM viajes_consolidados v WHERE NOT EXISTS (SELECT 1 FROM pedidos WHERE viaje_id = v.id);

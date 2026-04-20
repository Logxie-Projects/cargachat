SELECT estado, viaje_id IS NOT NULL AS con_viaje, COUNT(*) AS n
FROM pedidos GROUP BY 1, 2 ORDER BY 1, 2;

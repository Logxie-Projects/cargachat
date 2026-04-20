SELECT pedido_ref, estado, to_char(created_at, 'MM-DD HH24:MI') AS creado,
       viaje_id IS NOT NULL AS en_viaje, COALESCE(revision_notas, '') AS notas
FROM pedidos
WHERE pedido_ref LIKE 'TIT-00000124' OR pedido_ref LIKE 'SOLICTUDES%SEPT 2025%'
ORDER BY pedido_ref, created_at;

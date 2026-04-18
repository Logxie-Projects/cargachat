-- Ver clientes existentes y cliente_ids de pedidos sin_consolidar
SELECT 'clientes existentes' AS seccion, id::text AS id_o_ref, nombre AS dato, NULL::int AS n
FROM clientes
UNION ALL
SELECT 'cliente_ids únicos en pedidos sin_consolidar', cliente_id::text, NULL, COUNT(*)::int
FROM pedidos
WHERE estado = 'sin_consolidar'
GROUP BY cliente_id
ORDER BY seccion, id_o_ref;

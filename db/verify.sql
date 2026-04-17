-- Verificación del estado del Módulo 2 post-migración
SELECT 'clientes' AS tabla, COUNT(*) AS n FROM clientes
UNION ALL
SELECT 'viajes_consolidados', COUNT(*) FROM viajes_consolidados
UNION ALL
SELECT 'pedidos', COUNT(*) FROM pedidos
UNION ALL
SELECT 'pedidos con cliente_id', COUNT(*) FROM pedidos WHERE cliente_id IS NOT NULL
UNION ALL
SELECT 'pedidos sin cliente_id (debe ser 0)', COUNT(*) FROM pedidos WHERE cliente_id IS NULL
UNION ALL
SELECT 'viajes con cliente_id', COUNT(*) FROM viajes_consolidados WHERE cliente_id IS NOT NULL
UNION ALL
SELECT 'viajes sin cliente_id', COUNT(*) FROM viajes_consolidados WHERE cliente_id IS NULL;

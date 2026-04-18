-- 1) Muestra de 5 pedidos sin_consolidar con TODOS los campos "cliente"
SELECT
  pedido_ref,
  empresa,
  cliente_nombre,
  contacto_nombre,
  origen,
  destino
FROM pedidos
WHERE estado = 'sin_consolidar'
ORDER BY fecha_cargue DESC NULLS LAST
LIMIT 5;

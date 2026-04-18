-- Verifica que el smoke test no dejó rastro
SELECT
  (SELECT COUNT(*) FROM viajes_consolidados WHERE observaciones LIKE 'SMOKE_TEST%') AS viajes_smoke,
  (SELECT COUNT(*) FROM perfiles WHERE email = '_smoke@logxie.com')                 AS perfiles_smoke,
  (SELECT COUNT(*) FROM ofertas WHERE comentario = 'SMOKE offer')                   AS ofertas_smoke,
  (SELECT COUNT(*) FROM acciones_operador WHERE metadata->>'razon' LIKE 'Ridge%')   AS acciones_smoke,
  (SELECT COUNT(*) FROM pedidos WHERE estado = 'sin_consolidar')                    AS pedidos_sin_consolidar;

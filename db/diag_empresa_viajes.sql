-- Qué estados originales del Sheet tienen los 508 viajes "confirmados"
SELECT estado_original, COUNT(*) AS n,
       MIN(fecha_cargue)::date AS desde,
       MAX(fecha_cargue)::date AS hasta,
       MAX(fecha_cargue) < (now() - interval '30 days') AS todos_viejos_30d
FROM viajes_consolidados
WHERE estado = 'confirmado'
GROUP BY estado_original
ORDER BY n DESC;

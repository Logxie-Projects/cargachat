-- Distribución de variantes de "empresa" en viajes_consolidados
SELECT empresa, COUNT(*) AS n, MIN(fecha_cargue)::date AS desde, MAX(fecha_cargue)::date AS hasta
FROM viajes_consolidados
GROUP BY empresa
ORDER BY n DESC;

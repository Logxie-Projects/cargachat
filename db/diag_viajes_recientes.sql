SELECT fuente, COUNT(*) AS n,
       COUNT(*) FILTER (WHERE viaje_ref LIKE 'RT-TOTAL-%') AS rt_total,
       COUNT(*) FILTER (WHERE viaje_ref LIKE 'NF-%')       AS nf,
       MIN(created_at)::date AS primero,
       MAX(created_at)::date AS ultimo
FROM viajes_consolidados
GROUP BY fuente
ORDER BY n DESC;

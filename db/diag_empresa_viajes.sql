SELECT empresa, COUNT(*) AS n FROM viajes_consolidados GROUP BY empresa ORDER BY n DESC;

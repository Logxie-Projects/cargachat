-- ¿Cómo se ven los 1281 migrados? ¿tienen proveedor? ¿qué estado?
SELECT
  estado,
  CASE WHEN proveedor IS NOT NULL AND proveedor <> '' THEN 'CON proveedor texto' ELSE 'sin proveedor' END AS tiene_prov,
  CASE WHEN transportadora_id IS NOT NULL THEN 'CON FK' ELSE 'sin FK' END AS tiene_fk,
  COUNT(*) AS n,
  MIN(fecha_cargue::date) AS desde,
  MAX(fecha_cargue::date) AS hasta
FROM viajes_consolidados
WHERE fuente = 'sheet_asignados'
GROUP BY 1,2,3
ORDER BY n DESC;

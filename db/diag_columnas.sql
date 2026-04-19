-- Listar todas las columnas de viajes_consolidados y pedidos
SELECT
  table_name,
  column_name,
  data_type,
  CASE WHEN is_nullable = 'YES' THEN '' ELSE 'NOT NULL' END AS nn
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('viajes_consolidados','pedidos')
ORDER BY table_name, ordinal_position;

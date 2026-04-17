-- ============================================================
-- LINK pedidos.viaje_id desde viajes_consolidados.consecutivos
--
-- Reconstruye la FK perdida en la migración legacy (el Apps Script
-- guarda los pedidos_refs como texto concatenado en la columna
-- consecutivos, no como junction table).
--
-- Idempotente: solo toca pedidos donde viaje_id IS NULL.
-- Maneja rangos tipo "TIT-00001278 - TIT-00001294" expandiéndolos.
-- ============================================================

-- Función helper: expande una cadena de consecutivos a array de pedido_refs
-- Ejemplos:
--   'TIT-1280'                              → ['TIT-1280']
--   'RM-65853, RM-65854'                    → ['RM-65853', 'RM-65854']
--   'TIT-00001278 - TIT-00001294, TIT-1293' → ['TIT-00001278', ..., 'TIT-00001294', 'TIT-1293']
CREATE OR REPLACE FUNCTION expand_consecutivos(consec text)
RETURNS text[] AS $$
DECLARE
  tokens text[];
  result text[] := ARRAY[]::text[];
  token  text;
  m      text[];
  prefix text;
  width  int;
  i      bigint;
BEGIN
  IF consec IS NULL OR trim(consec) = '' THEN
    RETURN ARRAY[]::text[];
  END IF;

  tokens := regexp_split_to_array(consec, E'\\s*,\\s*');

  FOREACH token IN ARRAY tokens LOOP
    token := trim(token);
    IF token = '' THEN CONTINUE; END IF;

    -- Detectar rango: "PREFIX-NUMBER - PREFIX-NUMBER"
    m := regexp_match(token, '^([A-Z]+-)(\d+)\s+-\s+\1(\d+)$');
    IF m IS NOT NULL THEN
      prefix := m[1];
      width  := length(m[2]);
      FOR i IN m[2]::bigint..m[3]::bigint LOOP
        result := array_append(result, prefix || lpad(i::text, width, '0'));
      END LOOP;
    ELSE
      result := array_append(result, token);
    END IF;
  END LOOP;

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Backfill viaje_id con prioridad:
--   1. Viaje con mismo cliente_id (match exacto del cliente)
--   2. Viaje con cliente_id NULL (consolidación multi-empresa — match compatible)
--   3. Desempate: viaje más reciente (created_at DESC)
WITH matches AS (
  SELECT DISTINCT ON (p.id)
    p.id AS pedido_id,
    v.id AS viaje_id_nuevo
  FROM pedidos p
  JOIN viajes_consolidados v
    ON p.pedido_ref = ANY(expand_consecutivos(v.consecutivos))
   AND (v.cliente_id = p.cliente_id OR v.cliente_id IS NULL)
  WHERE p.viaje_id IS NULL
    AND p.pedido_ref IS NOT NULL
  ORDER BY p.id,
    CASE WHEN v.cliente_id = p.cliente_id THEN 1 ELSE 2 END,
    v.created_at DESC
)
UPDATE pedidos p
SET viaje_id = m.viaje_id_nuevo
FROM matches m
WHERE m.pedido_id = p.id;

-- Reporte
SELECT 'pedidos con viaje_id'                               AS metrica, COUNT(*) AS n FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'pedidos sin viaje_id (nunca consolidados o sin match)', COUNT(*)     FROM pedidos WHERE viaje_id IS NULL
UNION ALL SELECT 'viajes con al menos 1 pedido linkeado',               COUNT(DISTINCT viaje_id) FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'viajes totales',                                      COUNT(*)     FROM viajes_consolidados;

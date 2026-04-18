-- ============================================================
-- link_pedidos_viajes_v2.sql (optimizado)
--
-- v2: usa raw_payload->>'PEDIDOS_INCLUIDOS' como fuente primaria
-- (más rica que consecutivos en casos del bug del Apps Script del Sheet).
--
-- Optimización clave: materializa (viaje_id, canonical_ref) una sola vez
-- en un CTE y luego hace hash-join contra pedidos. Así evitamos parsear
-- raw_payload millones de veces en nested-loop.
--
-- Idempotente. Solo toca pedidos huérfanos (viaje_id IS NULL).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- Helpers (idempotentes)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION safe_json_get(raw text, key text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN (raw::jsonb)->>key;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION canonicalize_pedido_ref(ref text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  cleaned text;
  m text[];
BEGIN
  IF ref IS NULL OR trim(ref) = '' THEN RETURN NULL; END IF;
  cleaned := upper(regexp_replace(trim(ref), '\s+', '', 'g'));
  m := regexp_match(cleaned, '^([A-Z]+)-0*(\d+)');
  IF m IS NULL THEN RETURN cleaned; END IF;
  RETURN m[1] || '-' || m[2];
END;
$$;

CREATE OR REPLACE FUNCTION expand_consecutivos_v2(consec text)
RETURNS text[]
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  tokens text[];
  result text[] := ARRAY[]::text[];
  token  text;
  canon  text;
  m      text[];
  prefix text;
  i      bigint;
BEGIN
  IF consec IS NULL OR trim(consec) = '' THEN
    RETURN ARRAY[]::text[];
  END IF;

  tokens := regexp_split_to_array(consec, '[,/]');

  FOREACH token IN ARRAY tokens LOOP
    token := trim(token);
    IF token = '' THEN CONTINUE; END IF;

    m := regexp_match(
      upper(regexp_replace(token, '\s+', ' ', 'g')),
      '^([A-Z]+)-0*(\d+)\s+-\s+\1-0*(\d+)$'
    );
    IF m IS NOT NULL THEN
      prefix := m[1];
      FOR i IN m[2]::bigint..m[3]::bigint LOOP
        result := array_append(result, prefix || '-' || i::text);
      END LOOP;
    ELSE
      canon := canonicalize_pedido_ref(token);
      IF canon IS NOT NULL THEN
        result := array_append(result, canon);
      END IF;
    END IF;
  END LOOP;

  RETURN result;
END;
$$;

-- ------------------------------------------------------------
-- Backfill v2 OPTIMIZADO
--   1. viaje_refs: expand + unnest UNA vez por viaje (~1281 filas → ~4000-5000 pairs)
--   2. matches: hash-join contra pedidos huérfanos
--   3. UPDATE con prioridad cliente exacto > compatible > más reciente
-- ------------------------------------------------------------
WITH viaje_refs AS (
  SELECT
    v.id         AS viaje_id,
    v.cliente_id AS cliente_id,
    v.created_at,
    unnest(
      expand_consecutivos_v2(
        COALESCE(
          safe_json_get(v.raw_payload, 'PEDIDOS_INCLUIDOS'),
          v.consecutivos
        )
      )
    ) AS canon_ref
  FROM viajes_consolidados v
),
matches AS (
  SELECT DISTINCT ON (p.id)
    p.id           AS pedido_id,
    vr.viaje_id    AS viaje_id_nuevo
  FROM pedidos p
  JOIN viaje_refs vr
    ON canonicalize_pedido_ref(p.pedido_ref) = vr.canon_ref
   AND (vr.cliente_id = p.cliente_id OR vr.cliente_id IS NULL)
  WHERE p.viaje_id IS NULL
    AND p.pedido_ref IS NOT NULL
  ORDER BY p.id,
    CASE WHEN vr.cliente_id = p.cliente_id THEN 1 ELSE 2 END,
    vr.created_at DESC
)
UPDATE pedidos p
SET viaje_id = m.viaje_id_nuevo,
    estado   = CASE WHEN p.estado = 'sin_consolidar' THEN 'consolidado' ELSE p.estado END
FROM matches m
WHERE m.pedido_id = p.id;

COMMIT;

-- ------------------------------------------------------------
-- Reporte final
-- ------------------------------------------------------------
SELECT 'pedidos con viaje_id'             AS metrica, COUNT(*) AS n FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'pedidos huérfanos',        COUNT(*) FROM pedidos WHERE viaje_id IS NULL
UNION ALL SELECT 'viajes con >=1 pedido',    COUNT(DISTINCT viaje_id) FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'viajes totales',           COUNT(*) FROM viajes_consolidados;

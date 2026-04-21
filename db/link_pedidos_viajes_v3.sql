-- ============================================================
-- Linker v3: parser correcto según regla del operador
--
-- REGLA CLAVE (Bernardo 2026-04-20):
--   - Separador entre pedidos distintos: SOLO "," (coma)
--   - "70456-70457" o "7898/7899" son ALIASES del mismo pedido
--     (NO un rango de 2+ pedidos). El pedido puede tener 2 refs
--     porque se re-emitió, se corrigió, o tiene doble referencia.
--
-- Implementación:
--   1. Split por ","  → cada token = 1 pedido lógico
--   2. Dentro del token, extraer TODAS las refs (prefijo + número)
--      con regex global. Los números sin prefijo heredan el último
--      prefijo visto en el mismo token.
--   3. Emit todas las refs → linker matchea si el pedido en BD
--      tiene ref = cualquiera de los aliases.
--
-- Ejemplos:
--   "RM-72778, RM-72779"           → [RM-72778, RM-72779]         (2 pedidos)
--   "RM-72781-72803"               → [RM-72781, RM-72803]         (1 pedido, 2 aliases)
--   "RM-72782/72783/72784"         → [RM-72782, RM-72783, RM-72784] (1 pedido, 3 aliases)
--   "RM-00006351 RM-00006353"      → [RM-6351, RM-6353]           (1 pedido, 2 aliases)
--   "TI-54710 - TIT-2188"          → [TI-54710, TIT-2188]         (1 pedido, 2 prefijos)
--   "DEVOLUCION, RM-72777"         → [RM-72777]                    (DEVOLUCION ignorado)
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION expand_consecutivos_v3(consec text)
RETURNS text[]
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  result         text[] := ARRAY[]::text[];
  tokens         text[];
  token          text;
  current_prefix text;
  pairs          text[];
BEGIN
  IF consec IS NULL OR trim(consec) = '' THEN RETURN ARRAY[]::text[]; END IF;

  consec := upper(regexp_replace(consec, '\s+', ' ', 'g'));
  tokens := regexp_split_to_array(consec, ',');

  FOREACH token IN ARRAY tokens LOOP
    token := trim(token);
    IF token = '' THEN CONTINUE; END IF;
    -- Normalizar espacios alrededor de dashes: "TI -00001968" → "TI-00001968"
    -- (preserva espacios entre refs distintas: "RM-6070 RM-6071")
    token := regexp_replace(token, '\s*-\s*', '-', 'g');
    -- Normalizar espacio entre prefijo y número: "RM 67705" → "RM-67705"
    token := regexp_replace(token, '([A-Z]+)\s+(\d)', '\1-\2', 'g');
    current_prefix := NULL;

    -- Extrae TODAS las refs (prefijo-número o número suelto) del token
    FOR pairs IN SELECT regexp_matches(token, '([A-Z]+)?-?(\d+)', 'g') LOOP
      IF pairs[1] IS NOT NULL AND pairs[1] <> '' THEN
        current_prefix := pairs[1];
      END IF;
      IF current_prefix IS NOT NULL THEN
        result := array_append(result, current_prefix || '-' || ltrim(pairs[2], '0'));
      END IF;
    END LOOP;
  END LOOP;

  RETURN result;
END;
$$;

-- Tests inline
DO $$
BEGIN
  ASSERT expand_consecutivos_v3('RM-72778, RM-72779') = ARRAY['RM-72778','RM-72779'];
  ASSERT expand_consecutivos_v3('RM-72781 - 72803') = ARRAY['RM-72781','RM-72803'];
  ASSERT expand_consecutivos_v3('RM-72782/72783/72784') = ARRAY['RM-72782','RM-72783','RM-72784'];
  ASSERT expand_consecutivos_v3('RM-00006351 RM-00006353 RM-00006352') = ARRAY['RM-6351','RM-6353','RM-6352'];
  ASSERT expand_consecutivos_v3('TI-54710 - TIT-2188') = ARRAY['TI-54710','TIT-2188'];
  ASSERT expand_consecutivos_v3('DEVOLUCION, RM-72777') = ARRAY['RM-72777'];
  ASSERT expand_consecutivos_v3('RM-73020 / 73035, RM-73023') = ARRAY['RM-73020','RM-73035','RM-73023'];
  ASSERT expand_consecutivos_v3('RM-70325 - 73028') = ARRAY['RM-70325','RM-73028'];
  ASSERT expand_consecutivos_v3(NULL) = ARRAY[]::text[];
  RAISE NOTICE 'expand_consecutivos_v3 tests OK';
END $$;

-- Re-link huérfanos con parser corregido
WITH viaje_refs AS (
  SELECT
    v.id         AS viaje_id,
    v.cliente_id AS cliente_id,
    v.created_at,
    unnest(
      expand_consecutivos_v3(
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

-- Reporte
SELECT 'linkeados' AS m, COUNT(*) AS n FROM pedidos WHERE viaje_id IS NOT NULL
UNION ALL SELECT 'huérfanos', COUNT(*) FROM pedidos WHERE viaje_id IS NULL;

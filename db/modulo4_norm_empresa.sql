-- ============================================================
-- Normalizador de empresa consolidada
--
-- Canonicaliza cualquier variante de empresa a formato único:
--   - split por coma, trim cada parte, uppercase, dedupe, sort asc, join ", "
--
-- Ejemplos:
--   "AVGUST"           → "AVGUST"
--   "FATECO"           → "FATECO"
--   "AVGUST, FATECO"   → "AVGUST, FATECO"
--   "FATECO, AVGUST"   → "AVGUST, FATECO"
--   "FATECO , AVGUST"  → "AVGUST, FATECO"
--   "avgust,fateco"    → "AVGUST, FATECO"
--   ""                 → NULL
--
-- Integrado en fn_sync_viajes_batch (UPDATE + INSERT) para prevenir
-- que futuros syncs re-introduzcan variantes feas.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION _norm_empresa(raw text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN raw IS NULL OR trim(raw) = '' THEN NULL
    ELSE (
      SELECT string_agg(v, ', ' ORDER BY v)
      FROM (
        SELECT DISTINCT upper(trim(v)) AS v
        FROM unnest(string_to_array(raw, ',')) AS v
        WHERE trim(v) <> ''
      ) t
    )
  END;
$$;

-- Test inline
DO $$
BEGIN
  ASSERT _norm_empresa('AVGUST') = 'AVGUST';
  ASSERT _norm_empresa('FATECO, AVGUST') = 'AVGUST, FATECO';
  ASSERT _norm_empresa('FATECO , AVGUST') = 'AVGUST, FATECO';
  ASSERT _norm_empresa('avgust,fateco') = 'AVGUST, FATECO';
  ASSERT _norm_empresa('AVGUST, FATECO, AVGUST') = 'AVGUST, FATECO';
  ASSERT _norm_empresa('') IS NULL;
  ASSERT _norm_empresa(NULL) IS NULL;
  RAISE NOTICE 'norm_empresa tests OK';
END $$;

COMMIT;

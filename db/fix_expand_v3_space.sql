-- ============================================================
-- Fix expand_consecutivos_v3: normalizar espacios prefijo-número
--
-- Problema: refs como 'RM 67705' (con espacio en vez de dash) en
-- PEDIDOS_INCLUIDOS no se extraían porque el regex requería letras y
-- dígitos contiguos o separados solo por dash.
--
-- Fix: normalizar 'LETRAS espacio DIGITOS' a 'LETRAS-DIGITOS' antes
-- de aplicar el regex de extracción. Conserva separación entre refs
-- distintas (ej. 'RM-6070 RM-6071' sigue funcionando).
--
-- Tests inline. Idempotente.
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
    token := regexp_replace(token, '\s*-\s*', '-', 'g');
    -- Normalizar espacio entre prefijo y número: "RM 67705" → "RM-67705"
    -- (preserva separación entre refs distintas: "RM-6070 RM-6071")
    token := regexp_replace(token, '([A-Z]+)\s+(\d)', '\1-\2', 'g');
    current_prefix := NULL;

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

DO $$
BEGIN
  -- Caso del bug
  ASSERT expand_consecutivos_v3('RM 67705') = ARRAY['RM-67705'],
    format('RM 67705 esperado [RM-67705], got %s', expand_consecutivos_v3('RM 67705'));
  ASSERT expand_consecutivos_v3('RM-67694, RM-67695, RM-67969, RM 67705') = ARRAY['RM-67694','RM-67695','RM-67969','RM-67705'];
  -- Casos previos no rotos
  ASSERT expand_consecutivos_v3('RM-72778, RM-72779') = ARRAY['RM-72778','RM-72779'];
  ASSERT expand_consecutivos_v3('RM-72781 - 72803') = ARRAY['RM-72781','RM-72803'];
  ASSERT expand_consecutivos_v3('RM-00006351 RM-00006353 RM-00006352') = ARRAY['RM-6351','RM-6353','RM-6352'];
  ASSERT expand_consecutivos_v3('TI-54710 - TIT-2188') = ARRAY['TI-54710','TIT-2188'];
  ASSERT expand_consecutivos_v3('DEVOLUCION, RM-72777') = ARRAY['RM-72777'];
  RAISE NOTICE 'expand_consecutivos_v3 + space-fix tests OK';
END $$;

COMMIT;

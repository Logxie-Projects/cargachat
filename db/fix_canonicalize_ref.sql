-- ============================================================
-- Fix canonicalize_pedido_ref: dash opcional entre prefijo y número
--
-- Problema: refs sin dash ('RM 67705') canonicalizaban a 'RM67705'
-- mientras refs con dash ('RM-67705') a 'RM-67705'. El linker entonces
-- no encontraba el match aunque sea el mismo pedido.
--
-- Antes: regex `^([A-Z]+)-0*(\d+)` requería dash literal
-- Ahora: `^([A-Z]+)-?0*(\d+)` lo hace opcional
--
-- Idempotente. Re-corre linker para fixear los huérfanos afectados.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.canonicalize_pedido_ref(ref text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  cleaned text;
  m text[];
BEGIN
  IF ref IS NULL OR trim(ref) = '' THEN RETURN NULL; END IF;
  cleaned := upper(regexp_replace(trim(ref), '\s+', '', 'g'));
  -- Dash opcional para tolerar refs como 'RM 67705' (= 'RM-67705')
  m := regexp_match(cleaned, '^([A-Z]+)-?0*(\d+)');
  IF m IS NULL THEN RETURN cleaned; END IF;
  RETURN m[1] || '-' || m[2];
END;
$$;

-- Tests
DO $$
BEGIN
  ASSERT canonicalize_pedido_ref('RM-67705')   = 'RM-67705';
  ASSERT canonicalize_pedido_ref('RM 67705')   = 'RM-67705';  -- antes daba 'RM67705'
  ASSERT canonicalize_pedido_ref('RM67705')    = 'RM-67705';  -- antes daba 'RM67705'
  ASSERT canonicalize_pedido_ref('RM-00006441') = 'RM-6441';
  ASSERT canonicalize_pedido_ref('TIT-2203')   = 'TIT-2203';
  ASSERT canonicalize_pedido_ref(NULL)         IS NULL;
  RAISE NOTICE 'canonicalize_pedido_ref tests OK';
END $$;

COMMIT;

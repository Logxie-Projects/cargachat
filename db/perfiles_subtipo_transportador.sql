-- ============================================================
-- perfiles.subtipo_transportador
--
-- Para distinguir transportadoras empresa (multi-camión) de
-- transportadores independientes (1 camión, 1 persona).
-- El panel mi-netfleet.html condiciona tabs según este valor.
--
-- Default: NULL. Cuando se apruebe un usuario tipo='transportador',
-- operador Logxie decide el subtipo. Sin valor = se asume empresa.
-- ============================================================

BEGIN;

ALTER TABLE perfiles
  ADD COLUMN IF NOT EXISTS subtipo_transportador text
    CHECK (subtipo_transportador IS NULL OR subtipo_transportador IN ('empresa','independiente'));

COMMENT ON COLUMN perfiles.subtipo_transportador IS
  'empresa = multi-camión (ENTRAPETROL etc), independiente = 1 camión/1 persona. NULL = sin distinción aún.';

COMMIT;

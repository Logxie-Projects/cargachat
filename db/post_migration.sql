-- ============================================================
-- POST-MIGRACIÓN — Módulo 2
-- Ejecutar DESPUÉS de migrar viajes + pedidos históricos.
--
-- Qué hace:
--   1. Backfill cliente_id en pedidos basado en empresa (AVGUST/FATECO)
--   2. Backfill cliente_id en viajes_consolidados (nullable, solo cuando empresa es single)
--   3. Restaura NOT NULL en pedidos.cliente_id
--   4. Verificación final
-- ============================================================

BEGIN;

-- 0. Drop unique index — datos legacy tienen pedido_ref duplicados (re-entradas,
--    cancelaciones, correcciones). Se reemplaza por índice regular.
DROP INDEX IF EXISTS idx_pedidos_ref_cliente_unique;
CREATE INDEX IF NOT EXISTS idx_pedidos_ref_cliente ON pedidos(cliente_id, pedido_ref)
  WHERE pedido_ref IS NOT NULL;

-- 1. Backfill pedidos.cliente_id
UPDATE pedidos p
SET cliente_id = c.id
FROM clientes c
WHERE p.cliente_id IS NULL
  AND upper(trim(p.empresa)) = upper(trim(c.nombre));

-- 2. Backfill viajes_consolidados.cliente_id — solo si empresa es single (no 'AVGUST, FATECO')
UPDATE viajes_consolidados v
SET cliente_id = c.id
FROM clientes c
WHERE v.cliente_id IS NULL
  AND upper(trim(v.empresa)) = upper(trim(c.nombre));

-- 3. Verificar cuántos pedidos quedaron sin cliente_id (debería ser 0)
DO $$
DECLARE
  sin_cliente int;
  total int;
BEGIN
  SELECT COUNT(*) INTO sin_cliente FROM pedidos WHERE cliente_id IS NULL;
  SELECT COUNT(*) INTO total FROM pedidos;
  RAISE NOTICE 'Pedidos sin cliente_id: % de %', sin_cliente, total;
  IF sin_cliente > 0 THEN
    RAISE EXCEPTION 'Hay pedidos sin cliente_id — revisar valores de empresa que no matchean ningún cliente';
  END IF;
END $$;

-- 4. Restaurar NOT NULL en pedidos.cliente_id
ALTER TABLE pedidos ALTER COLUMN cliente_id SET NOT NULL;

COMMIT;

-- Verificación final
SELECT 'clientes' AS tabla, COUNT(*) AS n FROM clientes
UNION ALL
SELECT 'viajes_consolidados', COUNT(*) FROM viajes_consolidados
UNION ALL
SELECT 'pedidos', COUNT(*) FROM pedidos
UNION ALL
SELECT 'pedidos sin cliente_id', COUNT(*) FROM pedidos WHERE cliente_id IS NULL
UNION ALL
SELECT 'viajes sin cliente_id', COUNT(*) FROM viajes_consolidados WHERE cliente_id IS NULL;

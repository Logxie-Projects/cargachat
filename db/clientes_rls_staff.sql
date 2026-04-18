-- ============================================================
-- RLS clientes — permitir lectura/escritura a logxie_staff
-- y lectura al cliente_self_service de su propio cliente.
--
-- Fix: el UI control.html mostraba "5325d9" (primeros 6 chars del UUID)
-- porque RLS original solo exponía clientes a service_role.
-- ============================================================

BEGIN;

-- Staff lee todos los clientes
DROP POLICY IF EXISTS "staff_read" ON clientes;
CREATE POLICY "staff_read" ON clientes
  FOR SELECT TO authenticated
  USING (is_logxie_staff());

-- Staff escribe (crear nuevos clientes desde la UI de Admin futura)
DROP POLICY IF EXISTS "staff_write" ON clientes;
CREATE POLICY "staff_write" ON clientes
  FOR ALL TO authenticated
  USING (is_logxie_staff())
  WITH CHECK (is_logxie_staff());

-- Cliente self-service lee solo su propio cliente (preparado para M2 Nivel 3)
DROP POLICY IF EXISTS "self_service_read_own" ON clientes;
CREATE POLICY "self_service_read_own" ON clientes
  FOR SELECT TO authenticated
  USING (
    id IN (SELECT cliente_id FROM perfiles WHERE id = auth.uid() AND cliente_id IS NOT NULL)
  );

COMMIT;

-- Verificación: listar policies actuales
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'clientes'
ORDER BY policyname;

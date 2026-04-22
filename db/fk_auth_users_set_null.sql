-- ============================================================
-- FKs a auth.users — cambiar a ON DELETE SET NULL
--
-- Hoy las 10 FKs a auth.users tienen ON DELETE NO ACTION. Esto bloquea
-- cualquier intento de borrar un usuario que tenga historial (acciones_operador,
-- conductores creados, ofertas, etc.). Síntoma: "Database error deleting user".
--
-- Cambiamos a ON DELETE SET NULL para que:
--   · El delete del user sea posible (Edge Function admin_user → delete_user funciona)
--   · El historial se preserve (rows no se borran, solo pierden la referencia al user)
--   · El audit quede como "usuario desconocido" en vez de desaparecer
--
-- Excepción: perfiles.id sigue siendo ON DELETE CASCADE (el perfil es solo
-- metadatos del user — si borro el user, borro el perfil).
--
-- Caso especial: ofertas.usuario_id era NOT NULL. Lo hacemos nullable primero
-- para poder aplicar SET NULL.
--
-- Idempotente.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- Caso especial: ofertas.usuario_id era NOT NULL
-- ------------------------------------------------------------
ALTER TABLE ofertas ALTER COLUMN usuario_id DROP NOT NULL;

-- ------------------------------------------------------------
-- 10 FKs: DROP + RE-ADD con ON DELETE SET NULL
-- ------------------------------------------------------------

-- acciones_operador.user_id
ALTER TABLE acciones_operador DROP CONSTRAINT IF EXISTS acciones_operador_user_id_fkey;
ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- conductores.created_by
ALTER TABLE conductores DROP CONSTRAINT IF EXISTS conductores_created_by_fkey;
ALTER TABLE conductores
  ADD CONSTRAINT conductores_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- documentos_flota.subido_por
ALTER TABLE documentos_flota DROP CONSTRAINT IF EXISTS documentos_flota_subido_por_fkey;
ALTER TABLE documentos_flota
  ADD CONSTRAINT documentos_flota_subido_por_fkey
  FOREIGN KEY (subido_por) REFERENCES auth.users(id) ON DELETE SET NULL;

-- facturas.created_by
ALTER TABLE facturas DROP CONSTRAINT IF EXISTS facturas_created_by_fkey;
ALTER TABLE facturas
  ADD CONSTRAINT facturas_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- intentos_entrega.reportado_por
ALTER TABLE intentos_entrega DROP CONSTRAINT IF EXISTS intentos_entrega_reportado_por_fkey;
ALTER TABLE intentos_entrega
  ADD CONSTRAINT intentos_entrega_reportado_por_fkey
  FOREIGN KEY (reportado_por) REFERENCES auth.users(id) ON DELETE SET NULL;

-- invitaciones_subasta.invitado_por
ALTER TABLE invitaciones_subasta DROP CONSTRAINT IF EXISTS invitaciones_subasta_invitado_por_fkey;
ALTER TABLE invitaciones_subasta
  ADD CONSTRAINT invitaciones_subasta_invitado_por_fkey
  FOREIGN KEY (invitado_por) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ofertas.usuario_id (ahora nullable)
ALTER TABLE ofertas DROP CONSTRAINT IF EXISTS ofertas_usuario_id_fkey;
ALTER TABLE ofertas
  ADD CONSTRAINT ofertas_usuario_id_fkey
  FOREIGN KEY (usuario_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- pedidos.revisado_por
ALTER TABLE pedidos DROP CONSTRAINT IF EXISTS pedidos_revisado_por_fkey;
ALTER TABLE pedidos
  ADD CONSTRAINT pedidos_revisado_por_fkey
  FOREIGN KEY (revisado_por) REFERENCES auth.users(id) ON DELETE SET NULL;

-- scenarios_viaje.created_by
ALTER TABLE scenarios_viaje DROP CONSTRAINT IF EXISTS scenarios_viaje_created_by_fkey;
ALTER TABLE scenarios_viaje
  ADD CONSTRAINT scenarios_viaje_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- scenarios_viaje.promovido_por
ALTER TABLE scenarios_viaje DROP CONSTRAINT IF EXISTS scenarios_viaje_promovido_por_fkey;
ALTER TABLE scenarios_viaje
  ADD CONSTRAINT scenarios_viaje_promovido_por_fkey
  FOREIGN KEY (promovido_por) REFERENCES auth.users(id) ON DELETE SET NULL;

-- vehiculos.created_by
ALTER TABLE vehiculos DROP CONSTRAINT IF EXISTS vehiculos_created_by_fkey;
ALTER TABLE vehiculos
  ADD CONSTRAINT vehiculos_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- perfiles.id: NO tocar (sigue ON DELETE CASCADE — borrar user borra perfil).

COMMIT;

-- ============================================================
-- Verificación:
--   SELECT table_name, constraint_name, delete_rule
--     FROM information_schema.referential_constraints rc
--     JOIN information_schema.table_constraints tc USING (constraint_name, constraint_schema)
--    WHERE tc.table_schema = 'public'
--      AND unique_constraint_name IN (SELECT constraint_name FROM information_schema.table_constraints
--                                      WHERE table_schema='auth' AND table_name='users');
-- ============================================================

-- ============================================================
-- TABLA: perfiles
-- Propósito: datos del usuario ligados a auth.users
--   · Se crea automáticamente via trigger al registrarse (auth.users INSERT)
--   · 4 tipos: transportador | empresa | logxie_staff | cliente_self_service
--   · cliente_id solo populado para cliente_self_service (enforce via CHECK)
--
-- Diseño Módulo 4 — compatible desde el inicio (no requiere ALTER después).
-- Idempotente.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- Tabla
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS perfiles (
  id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       text,
  nombre      text,
  empresa     text,
  telefono    text,
  nit         text,
  tipo        text NOT NULL DEFAULT 'transportador'
              CHECK (tipo IN ('transportador', 'empresa', 'logxie_staff', 'cliente_self_service')),
  estado      text NOT NULL DEFAULT 'pendiente'
              CHECK (estado IN ('pendiente', 'aprobado', 'rechazado')),
  cliente_id  uuid REFERENCES clientes(id),
  created_at  timestamptz NOT NULL DEFAULT now(),

  -- Coherencia: cliente_id solo si tipo=cliente_self_service
  CONSTRAINT perfiles_cliente_id_coherence CHECK (
    (tipo = 'cliente_self_service' AND cliente_id IS NOT NULL)
    OR (tipo <> 'cliente_self_service' AND cliente_id IS NULL)
  )
);

-- ------------------------------------------------------------
-- Índices
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_perfiles_cliente_id
  ON perfiles(cliente_id) WHERE cliente_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_perfiles_tipo ON perfiles(tipo);
CREATE INDEX IF NOT EXISTS idx_perfiles_estado ON perfiles(estado);

-- ------------------------------------------------------------
-- Helper: is_logxie_staff()
-- SECURITY DEFINER evita recursión cuando RLS de perfiles
-- consulta perfiles para chequear el rol.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_logxie_staff()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM perfiles
    WHERE id = auth.uid() AND tipo = 'logxie_staff'
  );
$$;

-- ------------------------------------------------------------
-- Trigger handle_new_user()
-- Crea la fila en perfiles al registrarse en auth.users.
-- Lee campos opcionales de raw_user_meta_data (signUp options.data).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO perfiles (id, email, nombre, empresa, telefono, nit, tipo)
  VALUES (
    NEW.id,
    NEW.email,
    NULLIF(NEW.raw_user_meta_data->>'nombre', ''),
    NULLIF(NEW.raw_user_meta_data->>'empresa', ''),
    NULLIF(NEW.raw_user_meta_data->>'telefono', ''),
    NULLIF(NEW.raw_user_meta_data->>'nit', ''),
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'tipo', ''), 'transportador')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

-- Leer: propio perfil o staff ve todo
DROP POLICY IF EXISTS "read_own_or_staff" ON perfiles;
CREATE POLICY "read_own_or_staff" ON perfiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR is_logxie_staff());

-- Actualizar: propio perfil (salvo tipo y estado — solo staff los cambia)
DROP POLICY IF EXISTS "update_own" ON perfiles;
CREATE POLICY "update_own" ON perfiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Staff puede actualizar cualquier perfil (incluido estado: aprobar/rechazar)
DROP POLICY IF EXISTS "staff_update_all" ON perfiles;
CREATE POLICY "staff_update_all" ON perfiles
  FOR UPDATE TO authenticated
  USING (is_logxie_staff())
  WITH CHECK (is_logxie_staff());

-- INSERT directo: solo service_role (todo el mundo pasa por el trigger)
DROP POLICY IF EXISTS "service_role_all" ON perfiles;
CREATE POLICY "service_role_all" ON perfiles
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMIT;

-- ============================================================
-- POST-DEPLOY MANUAL
-- ============================================================
-- 1) Promover a Bernardo a logxie_staff después de que se registre:
--      UPDATE perfiles SET tipo = 'logxie_staff', estado = 'aprobado'
--       WHERE email = 'bernardoaristizabal@logxie.com';
--
-- 2) Verificación:
--      SELECT id, email, tipo, estado FROM perfiles;
--      SELECT count(*) FROM auth.users u
--        LEFT JOIN perfiles p ON p.id = u.id WHERE p.id IS NULL;
--      -- debería dar 0 (todos los auth.users tienen fila en perfiles)
-- ============================================================

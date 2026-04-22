-- ============================================================
-- ALTER perfiles — rol_transportadora
--
-- Campo informativo del rol funcional dentro de una transportadora:
--   · comercial    → oferta y acepta viajes (bidding)
--   · operativo    → asigna vehículo/conductor, actualiza tracking
--   · facturacion  → factura viajes finalizados
--
-- Solo aplica cuando tipo='transportador'. NULL para staff / empresa / cliente.
--
-- NO gate de acceso hoy — solo label/metadata. Preparación para cuando se quiera
-- restringir tabs en mi-netfleet por rol (sesión futura).
--
-- Idempotente.
-- ============================================================

BEGIN;

ALTER TABLE perfiles
  ADD COLUMN IF NOT EXISTS rol_transportadora text
    CHECK (rol_transportadora IS NULL OR rol_transportadora IN ('comercial','operativo','facturacion'));

COMMENT ON COLUMN perfiles.rol_transportadora IS
  'Rol funcional dentro de la transportadora: comercial | operativo | facturacion. Solo cuando tipo=transportador. Hoy informativo — no gate de acceso.';

CREATE INDEX IF NOT EXISTS idx_perfiles_rol_transportadora
  ON perfiles(rol_transportadora)
  WHERE rol_transportadora IS NOT NULL;

COMMIT;

-- ============================================================
-- Verificación:
--   \d perfiles
--   SELECT email, tipo, rol_transportadora FROM perfiles;
-- ============================================================

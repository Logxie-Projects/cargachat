-- ============================================================
-- Módulo 4 — RLS endurecido para aislamiento entre transportadoras
--
-- Problema que resuelve:
--   HOY `viajes_consolidados` + `pedidos` tienen policy `authenticated_all`
--   (USING true, WITH CHECK true). Cualquier transportador logueado hace
--   fetch('/rest/v1/viajes_consolidados') y ve TODOS los viajes, incluyendo
--   flete/proveedor/valor_mercancia de la competencia + pedidos con cliente
--   final, dirección, teléfono. La UI filtra visualmente pero la DB no.
--
-- Cambios:
--   1. Backfill `viajes_consolidados.transportadora_id` para viajes legacy
--      sincronizados desde Sheet ASIGNADOS (que solo trae proveedor text)
--   2. DROP authenticated_all en viajes_consolidados + pedidos
--   3. Policies granulares:
--      - staff: todo
--      - transportadora autenticada:
--          * viajes asignados a ella (transportadora_id FK match)
--          * viajes pendientes con subasta_tipo=abierta (para ofertar)
--          * viajes con invitación activa en invitaciones_subasta
--          * pedidos de viajes asignados a ella (nada de cliente final ajeno)
--   4. Nada cambia para staff (sigue viendo todo)
--   5. La policy anon_select_publicos existente en viajes_consolidados
--      (landing) queda intacta
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Backfill transportadora_id desde proveedor text (7 seed)
-- ------------------------------------------------------------
-- Mapping explícito por substring. Conservador — solo matches seguros.
-- Los viajes con proveedor de transportadoras NO-seed quedan con FK=NULL
-- y solo los verá staff (correcto, porque no tienen cuenta de usuario).

WITH mapping AS (
  SELECT v.id AS viaje_id,
    CASE
      WHEN upper(v.proveedor) LIKE '%ENTRAPETROL%'          THEN (SELECT id FROM transportadoras WHERE nombre='ENTRAPETROL')
      WHEN upper(v.proveedor) LIKE '%LOGISTICA Y SERVICIOS JR%'
        OR upper(v.proveedor) LIKE '%JR LOGIS%'
        OR upper(v.proveedor) LIKE '%JR LOG%SAS%'
        OR upper(trim(v.proveedor)) = 'JR'                  THEN (SELECT id FROM transportadoras WHERE nombre='JR LOGÍSTICA')
      WHEN upper(v.proveedor) LIKE '%TRASAMER%'             THEN (SELECT id FROM transportadoras WHERE nombre='TRASAMER')
      WHEN upper(v.proveedor) LIKE '%NUEVA COLOMBIA%'       THEN (SELECT id FROM transportadoras WHERE nombre='TRANS NUEVA COLOMBIA')
      WHEN upper(v.proveedor) LIKE '%PRACARGO%'             THEN (SELECT id FROM transportadoras WHERE nombre='PRACARGO')
      WHEN upper(v.proveedor) LIKE '%GLOBAL LOG%'           THEN (SELECT id FROM transportadoras WHERE nombre='GLOBAL LOGÍSTICA')
      WHEN upper(v.proveedor) LIKE '%VIGIA%'
        OR upper(v.proveedor) LIKE '%VIGÍA%'                THEN (SELECT id FROM transportadoras WHERE nombre='VIGÍA')
      ELSE NULL
    END AS transp_match_id
  FROM viajes_consolidados v
  WHERE v.proveedor IS NOT NULL
    AND trim(v.proveedor) <> ''
    AND v.transportadora_id IS NULL
)
UPDATE viajes_consolidados v
  SET transportadora_id = m.transp_match_id
  FROM mapping m
  WHERE m.viaje_id = v.id AND m.transp_match_id IS NOT NULL;

-- (no audit — acciones_operador requiere entidad_id y el backfill es bulk)

-- ------------------------------------------------------------
-- 2. viajes_consolidados — drop permisivo + policies granulares
-- ------------------------------------------------------------
DROP POLICY IF EXISTS authenticated_all ON viajes_consolidados;
DROP POLICY IF EXISTS viajes_staff_all            ON viajes_consolidados;
DROP POLICY IF EXISTS viajes_transp_ver_propios   ON viajes_consolidados;
DROP POLICY IF EXISTS viajes_transp_ver_subasta   ON viajes_consolidados;
DROP POLICY IF EXISTS viajes_transp_ver_invitados ON viajes_consolidados;

-- Staff: todo (ALL)
CREATE POLICY viajes_staff_all ON viajes_consolidados
  FOR ALL TO authenticated
  USING      (is_logxie_staff())
  WITH CHECK (is_logxie_staff());

-- Transportadora: SELECT sólo viajes asignados a ella
CREATE POLICY viajes_transp_ver_propios ON viajes_consolidados
  FOR SELECT TO authenticated
  USING (
    transportadora_id IS NOT NULL
    AND transportadora_id = _mi_transportadora_id()
  );

-- Transportadora: SELECT viajes pendientes con subasta abierta (para ofertar)
CREATE POLICY viajes_transp_ver_subasta ON viajes_consolidados
  FOR SELECT TO authenticated
  USING (
    _mi_transportadora_id() IS NOT NULL
    AND estado = 'pendiente'
    AND (proveedor IS NULL OR trim(proveedor) = '')
    AND subasta_tipo = 'abierta'
    AND publicado_at IS NOT NULL
  );

-- Transportadora: SELECT viajes con invitación activa (subasta cerrada)
CREATE POLICY viajes_transp_ver_invitados ON viajes_consolidados
  FOR SELECT TO authenticated
  USING (
    _mi_transportadora_id() IS NOT NULL
    AND id IN (
      SELECT viaje_id FROM invitaciones_subasta
      WHERE transportadora_id = _mi_transportadora_id()
    )
  );

-- service_role: todo (ya existe como service_role_all, la dejamos)
-- anon_select_publicos: landing pública (estado IN pendiente,confirmado), intacta

-- ------------------------------------------------------------
-- 3. pedidos — drop permisivo + policies granulares
-- ------------------------------------------------------------
DROP POLICY IF EXISTS authenticated_all           ON pedidos;
DROP POLICY IF EXISTS pedidos_staff_all           ON pedidos;
DROP POLICY IF EXISTS pedidos_transp_ver_propios  ON pedidos;

-- Staff: todo
CREATE POLICY pedidos_staff_all ON pedidos
  FOR ALL TO authenticated
  USING      (is_logxie_staff())
  WITH CHECK (is_logxie_staff());

-- Transportadora: SELECT sólo pedidos de viajes asignados a ella
-- (cliente final, dirección, tel, valor_mercancia — NUNCA expuesto antes de ganar)
CREATE POLICY pedidos_transp_ver_propios ON pedidos
  FOR SELECT TO authenticated
  USING (
    _mi_transportadora_id() IS NOT NULL
    AND viaje_id IN (
      SELECT id FROM viajes_consolidados
      WHERE transportadora_id = _mi_transportadora_id()
    )
  );

-- service_role: todo (service_role_all ya existe, intacta)

COMMIT;

-- ============================================================
-- Verificación post-migración (correr manual como staff):
--
-- SELECT count(*), count(transportadora_id), count(*)-count(transportadora_id) AS sin_fk
--   FROM viajes_consolidados WHERE proveedor IS NOT NULL AND trim(proveedor) <> '';
--
-- Debería mostrar ~1145/1300 con FK, ~155 sin (las 9 transportadoras no-seed + TR REEMPLAZADA)
--
-- SELECT policyname, cmd FROM pg_policies
--   WHERE tablename IN ('viajes_consolidados','pedidos') ORDER BY tablename, policyname;
-- ============================================================

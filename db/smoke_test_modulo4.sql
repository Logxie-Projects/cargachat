-- ============================================================
-- SMOKE TEST — Módulo 4 backend
--
-- Ejercita el ciclo completo: consolidar → publicar → adjudicar
--   1. Promueve un auth.users existente a logxie_staff (perfiles row)
--   2. Simula JWT de ese user vía set_config(request.jwt.claims)
--   3. Elige 3 pedidos sin_consolidar reales del mismo cliente
--   4. fn_consolidar_pedidos → fn_publicar_viaje → INSERT oferta → fn_adjudicar_oferta
--   5. Verifica invariantes (estados, agregados, audit trail)
--   6. ROLLBACK al final — no persiste NADA (ni el viaje, ni la oferta, ni el perfil staff)
--
-- Correr:
--   python db/run_migration.py --file db/smoke_test_modulo4.sql
--
-- Seguro de re-ejecutar N veces. Solo valida; no deja datos de prueba.
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_staff_id    uuid;
  v_transp_id   uuid;
  v_pedido_ids  uuid[];
  v_viaje_id    uuid;
  v_oferta_id   uuid;
  v_cnt         int;
  v_estado      text;
  v_flete       numeric;
BEGIN
  -- ----------------------------------------------------------------
  -- 1) Elegir un auth.users existente y promoverlo a logxie_staff
  -- ----------------------------------------------------------------
  SELECT id INTO v_staff_id FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_staff_id IS NULL THEN
    RAISE EXCEPTION 'SMOKE FAIL · No hay auth.users — el test requiere ≥1 usuario registrado';
  END IF;
  RAISE NOTICE '[1] staff_id = %', v_staff_id;

  -- Perfiles row (idempotente — rollback igual revierte)
  INSERT INTO perfiles (id, email, tipo, estado)
  VALUES (v_staff_id, '_smoke@logxie.com', 'logxie_staff', 'aprobado')
  ON CONFLICT (id) DO UPDATE
    SET tipo = 'logxie_staff', estado = 'aprobado';

  -- ----------------------------------------------------------------
  -- 2) Simular JWT → auth.uid() devolverá v_staff_id
  -- ----------------------------------------------------------------
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_staff_id::text, 'role', 'authenticated')::text,
    true
  );

  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'SMOKE FAIL · is_logxie_staff() devolvió false tras setear claims';
  END IF;
  RAISE NOTICE '[2] is_logxie_staff() = TRUE';

  -- ----------------------------------------------------------------
  -- 3) Elegir 3 pedidos sin_consolidar del mismo cliente
  -- ----------------------------------------------------------------
  SELECT array_agg(id ORDER BY id) INTO v_pedido_ids
  FROM (
    SELECT id
      FROM pedidos
     WHERE estado = 'sin_consolidar'
       AND cliente_id = (
         SELECT cliente_id
           FROM pedidos
          WHERE estado = 'sin_consolidar' AND cliente_id IS NOT NULL
          GROUP BY cliente_id
          ORDER BY COUNT(*) DESC
          LIMIT 1
       )
     ORDER BY created_at
     LIMIT 3
  ) t;

  IF v_pedido_ids IS NULL OR array_length(v_pedido_ids, 1) < 3 THEN
    RAISE EXCEPTION 'SMOKE FAIL · menos de 3 pedidos sin_consolidar disponibles (encontrados %)',
      COALESCE(array_length(v_pedido_ids, 1), 0);
  END IF;
  RAISE NOTICE '[3] 3 pedidos elegidos: %', v_pedido_ids;

  -- ----------------------------------------------------------------
  -- 4) fn_consolidar_pedidos
  -- ----------------------------------------------------------------
  v_viaje_id := fn_consolidar_pedidos(
    v_pedido_ids,
    jsonb_build_object(
      'observaciones', 'SMOKE_TEST_' || to_char(now(), 'YYYYMMDD_HH24MISS'),
      'flete_total',   2500000
    )
  );
  RAISE NOTICE '[4] viaje consolidado = %', v_viaje_id;

  -- Invariante: los 3 pedidos están consolidado + viaje_id
  SELECT COUNT(*) INTO v_cnt
    FROM pedidos
   WHERE id = ANY(v_pedido_ids) AND estado = 'consolidado' AND viaje_id = v_viaje_id;
  IF v_cnt <> 3 THEN
    RAISE EXCEPTION 'SMOKE FAIL · esperaba 3 pedidos consolidados+linkeados, encontré %', v_cnt;
  END IF;

  -- Invariante: el viaje quedó pendiente + agregados poblados
  SELECT estado, flete_total INTO v_estado, v_flete
    FROM viajes_consolidados WHERE id = v_viaje_id;
  IF v_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'SMOKE FAIL · viaje debía quedar pendiente, quedó %', v_estado;
  END IF;
  IF v_flete <> 2500000 THEN
    RAISE EXCEPTION 'SMOKE FAIL · flete_total = % (esperaba 2500000)', v_flete;
  END IF;

  -- ----------------------------------------------------------------
  -- 5) fn_ajustar_precio_viaje — simular que el operador revisa Ridge y cambia precio
  -- ----------------------------------------------------------------
  PERFORM fn_ajustar_precio_viaje(v_viaje_id, 2800000, 'Ridge sugirió 2.8M, 12% sobre Ridge');
  SELECT flete_total INTO v_flete FROM viajes_consolidados WHERE id = v_viaje_id;
  IF v_flete <> 2800000 THEN
    RAISE EXCEPTION 'SMOKE FAIL · ajuste de precio no aplicó (flete=%)', v_flete;
  END IF;
  RAISE NOTICE '[5] precio ajustado a 2.800.000';

  -- ----------------------------------------------------------------
  -- 6) fn_publicar_viaje
  -- ----------------------------------------------------------------
  PERFORM fn_publicar_viaje(v_viaje_id, 'abierta');
  SELECT publicado_at IS NOT NULL INTO v_estado FROM viajes_consolidados WHERE id = v_viaje_id;
  IF v_estado::text <> 'true' THEN
    RAISE EXCEPTION 'SMOKE FAIL · publicado_at no se seteó';
  END IF;
  RAISE NOTICE '[6] viaje publicado (subasta abierta)';

  -- ----------------------------------------------------------------
  -- 7) INSERT oferta simulando un transportador
  --    (usamos el mismo v_staff_id como usuario_id — vale porque FK solo
  --     exige auth.users y RLS no aplica al superuser)
  -- ----------------------------------------------------------------
  SELECT id INTO v_transp_id FROM transportadoras WHERE nombre = 'ENTRAPETROL';
  IF v_transp_id IS NULL THEN
    RAISE EXCEPTION 'SMOKE FAIL · transportadora ENTRAPETROL no existe';
  END IF;

  INSERT INTO ofertas (viaje_id, transportadora_id, usuario_id, precio_oferta, comentario)
  VALUES (v_viaje_id, v_transp_id, v_staff_id, 2650000, 'SMOKE offer')
  RETURNING id INTO v_oferta_id;
  RAISE NOTICE '[7] oferta = %', v_oferta_id;

  -- ----------------------------------------------------------------
  -- 8) fn_adjudicar_oferta
  -- ----------------------------------------------------------------
  PERFORM fn_adjudicar_oferta(v_oferta_id);

  -- Invariante: viaje confirmado, con transportadora y oferta ganadora
  SELECT estado, flete_total INTO v_estado, v_flete
    FROM viajes_consolidados WHERE id = v_viaje_id;
  IF v_estado <> 'confirmado' THEN
    RAISE EXCEPTION 'SMOKE FAIL · viaje debía quedar confirmado, quedó %', v_estado;
  END IF;
  IF v_flete <> 2650000 THEN
    RAISE EXCEPTION 'SMOKE FAIL · flete del viaje debería ser 2650000 (precio oferta), es %', v_flete;
  END IF;

  -- Invariante: pedidos → asignado
  SELECT COUNT(*) INTO v_cnt
    FROM pedidos
   WHERE id = ANY(v_pedido_ids) AND estado = 'asignado';
  IF v_cnt <> 3 THEN
    RAISE EXCEPTION 'SMOKE FAIL · esperaba 3 pedidos asignados, encontré %', v_cnt;
  END IF;

  -- Invariante: oferta aceptada
  SELECT estado INTO v_estado FROM ofertas WHERE id = v_oferta_id;
  IF v_estado <> 'aceptada' THEN
    RAISE EXCEPTION 'SMOKE FAIL · oferta debía ser aceptada, es %', v_estado;
  END IF;
  RAISE NOTICE '[8] viaje confirmado, 3 pedidos asignados, oferta aceptada';

  -- ----------------------------------------------------------------
  -- 9) Audit trail: debería haber 4 acciones (consolidar, ajustar_precio, publicar, adjudicar)
  -- ----------------------------------------------------------------
  SELECT COUNT(*) INTO v_cnt
    FROM acciones_operador
   WHERE user_id = v_staff_id
     AND (entidad_id = v_viaje_id OR entidad_id = v_oferta_id);
  IF v_cnt <> 4 THEN
    RAISE EXCEPTION 'SMOKE FAIL · audit trail debería tener 4 acciones, tiene %', v_cnt;
  END IF;
  RAISE NOTICE '[9] audit trail OK (4 acciones)';

  -- Guardar el id para la query de output
  CREATE TEMP TABLE smoke_result ON COMMIT DROP AS
    SELECT v_viaje_id AS viaje_id, v_oferta_id AS oferta_id, v_staff_id AS staff_id;

  RAISE NOTICE '✓ SMOKE TEST OK — todas las invariantes validadas';
END$$;

-- ----------------------------------------------------------------
-- Output: resumen del estado final antes del rollback
-- ----------------------------------------------------------------
SELECT
  ao.accion                                    AS paso,
  ao.entidad_tipo                              AS sobre,
  to_char(ao.created_at, 'HH24:MI:SS.MS')      AS t,
  LEFT(COALESCE(
    ao.metadata->>'cantidad',
    ao.metadata->>'precio_nuevo',
    ao.metadata->>'subasta_tipo',
    ao.metadata->>'precio',
    ''
  ), 30)                                        AS dato
FROM acciones_operador ao, smoke_result sr
WHERE ao.user_id = sr.staff_id
  AND (ao.entidad_id = sr.viaje_id OR ao.entidad_id = sr.oferta_id)
ORDER BY ao.created_at;

ROLLBACK;

-- ============================================================
-- Módulo 4 — fn_reabrir_viaje + extensión CHECK acciones
--
-- Permite revertir un viaje `confirmado` de vuelta a `pendiente`
-- para corregir proveedor, añadir/quitar pedidos o desconsolidar.
--
-- Precondiciones:
--   - viaje.estado = 'confirmado' (si ya está en_ruta/entregado: bloqueado)
--   - operador = logxie_staff
--   - razón obligatoria
--
-- Efectos:
--   - transportadora_id, adjudicado_at, adjudicacion_tipo, oferta_ganadora_id → NULL
--   - publicado_at conservado (sigue publicado, solo sin proveedor)
--   - Si había oferta ganadora: vuelve a 'activa'; las rechazadas también vuelven a 'activa'
--   - Pedidos: asignado → consolidado
--   - Audit completo en acciones_operador
--
-- Idempotente: CREATE OR REPLACE + DROP CONSTRAINT idempotente.
-- ============================================================

BEGIN;

-- 1) Extender CHECK de acciones_operador.accion con 'reabrir'
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.acciones_operador'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%accion%'
  LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_accion_check
  CHECK (accion IN (
    'consolidar',
    'agregar_pedido',
    'quitar_pedido',
    'desconsolidar',
    'ajustar_precio',
    'publicar',
    'invitar',
    'asignar_directo',
    'adjudicar',
    'cancelar',
    'reasignar',
    'reabrir'
  ));

-- 2) fn_reabrir_viaje
CREATE OR REPLACE FUNCTION fn_reabrir_viaje(
  p_viaje_id uuid,
  p_razon    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado      text;
  v_transp_id         uuid;
  v_oferta_ganadora   uuid;
  v_adjudicacion_tipo text;
  v_pedidos_revertidos int;
  v_ofertas_reactivadas int;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede reabrir viajes';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para reabrir un viaje';
  END IF;

  SELECT estado, transportadora_id, oferta_ganadora_id, adjudicacion_tipo
    INTO v_viaje_estado, v_transp_id, v_oferta_ganadora, v_adjudicacion_tipo
    FROM viajes_consolidados WHERE id = p_viaje_id;

  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;

  IF v_viaje_estado <> 'confirmado' THEN
    RAISE EXCEPTION 'Solo se reabren viajes confirmados (estado actual: %). Para viajes en_ruta/entregado no se puede deshacer.', v_viaje_estado;
  END IF;

  -- Si fue adjudicación por subasta: reactivar todas las ofertas del viaje (ganadora + rechazadas)
  v_ofertas_reactivadas := 0;
  IF v_adjudicacion_tipo = 'subasta' THEN
    UPDATE ofertas SET estado = 'activa', cerrada_at = NULL
     WHERE viaje_id = p_viaje_id AND estado IN ('aceptada', 'rechazada');
    GET DIAGNOSTICS v_ofertas_reactivadas = ROW_COUNT;
  END IF;

  -- Pedidos: asignado → consolidado
  UPDATE pedidos SET estado = 'consolidado'
   WHERE viaje_id = p_viaje_id AND estado = 'asignado';
  GET DIAGNOSTICS v_pedidos_revertidos = ROW_COUNT;

  -- Viaje: limpiar datos de adjudicación, volver a pendiente
  -- publicado_at se conserva a propósito (si estaba en subasta, sigue publicado)
  UPDATE viajes_consolidados
  SET
    transportadora_id  = NULL,
    proveedor          = NULL,
    estado             = 'pendiente',
    adjudicado_at      = NULL,
    adjudicacion_tipo  = NULL,
    oferta_ganadora_id = NULL
  WHERE id = p_viaje_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'reabrir', 'viaje', p_viaje_id,
    jsonb_build_object(
      'transportadora_anterior_id', v_transp_id,
      'oferta_ganadora_anterior_id', v_oferta_ganadora,
      'adjudicacion_tipo_anterior', v_adjudicacion_tipo,
      'pedidos_revertidos', v_pedidos_revertidos,
      'ofertas_reactivadas', v_ofertas_reactivadas,
      'razon', p_razon
    ));
END;
$$;

COMMIT;

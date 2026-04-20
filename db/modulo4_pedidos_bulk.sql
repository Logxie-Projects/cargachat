-- ============================================================
-- fn_pedidos_cancelar_batch + fn_pedidos_resetear_batch + fn_pedido_clonar
--
-- Bulk operations sobre pedidos:
--   1. Cancelar N pedidos (estado=cancelado, razon obligatoria)
--   2. Resetear N pedidos (estado=sin_consolidar, viaje_id=NULL,
--      opcionalmente también revisado_at=NULL para volver a "Nuevos")
--   3. Clonar un pedido — duplica el row con mismo pedido_ref pero
--      viaje_id=NULL, estado=sin_consolidar, para permitir reintento
--      de entrega en un nuevo viaje (caso: primer intento no se cargó).
--
-- Idempotente.
-- ============================================================

BEGIN;

-- Extender CHECK acciones.accion
DO $$
DECLARE c record;
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
    'consolidar','agregar_pedido','quitar_pedido','desconsolidar',
    'ajustar_precio','publicar','invitar','asignar_directo',
    'adjudicar','cancelar','reasignar','reabrir',
    'sync_viajes','sync_pedidos',
    'revisar_pedido','desmarcar_revision',
    'cerrar','cerrar_batch','reabrir_cierre',
    'cancelar_pedidos_batch','resetear_pedidos_batch','clonar_pedido'
  ));

-- ============================================================
-- fn_pedidos_cancelar_batch
--   Marca N pedidos como cancelado. Mantiene viaje_id (histórico).
-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedidos_cancelar_batch(
  p_pedido_ids uuid[],
  p_razon      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cancelados int;
  v_ya_cancelados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede cancelar pedidos';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para cancelar pedidos';
  END IF;
  IF p_pedido_ids IS NULL OR array_length(p_pedido_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Lista de pedidos vacía';
  END IF;

  -- Contar los que ya están cancelados
  SELECT COUNT(*) INTO v_ya_cancelados FROM pedidos
   WHERE id = ANY(p_pedido_ids) AND estado = 'cancelado';

  UPDATE pedidos
  SET estado = 'cancelado',
      revision_notas = COALESCE(revision_notas || ' | ', '') || 'CANCELADO: ' || p_razon
  WHERE id = ANY(p_pedido_ids) AND estado <> 'cancelado';
  GET DIAGNOSTICS v_cancelados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cancelar_pedidos_batch', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'cancelados', v_cancelados,
      'ya_cancelados', v_ya_cancelados,
      'total_input', array_length(p_pedido_ids, 1),
      'razon', p_razon
    ));

  RETURN jsonb_build_object(
    'cancelados', v_cancelados,
    'ya_cancelados', v_ya_cancelados,
    'total_input', array_length(p_pedido_ids, 1)
  );
END;
$$;

-- ============================================================
-- fn_pedidos_resetear_batch
--   Libera N pedidos a estado sin_consolidar con viaje_id=NULL.
--   p_marcar_nuevo=true → también limpia revisado_at (pasan a "Nuevos")
--   p_marcar_nuevo=false → mantienen revisado_at (quedan en "Sin consolidar")
--   Funciona sobre cualquier estado (incluso cancelado — para rescatar).
-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedidos_resetear_batch(
  p_pedido_ids   uuid[],
  p_razon        text,
  p_marcar_nuevo boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reseteados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede resetear pedidos';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para resetear pedidos';
  END IF;
  IF p_pedido_ids IS NULL OR array_length(p_pedido_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Lista de pedidos vacía';
  END IF;

  UPDATE pedidos
  SET estado = 'sin_consolidar',
      viaje_id = NULL,
      revisado_at = CASE WHEN p_marcar_nuevo THEN NULL ELSE COALESCE(revisado_at, created_at) END,
      revision_notas = COALESCE(revision_notas || ' | ', '') || 'RESETEADO: ' || p_razon
  WHERE id = ANY(p_pedido_ids);
  GET DIAGNOSTICS v_reseteados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'resetear_pedidos_batch', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'reseteados', v_reseteados,
      'marcar_nuevo', p_marcar_nuevo,
      'razon', p_razon
    ));

  RETURN jsonb_build_object('reseteados', v_reseteados);
END;
$$;

-- ============================================================
-- fn_pedido_clonar
--   Duplica un pedido (mismo pedido_ref, nuevo id) para reintento.
--   El clon queda: estado=sin_consolidar, viaje_id=NULL,
--   revisado_at=now() (ya revisado, listo para consolidar),
--   revision_notas marca que es clon del pedido origen.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedido_clonar(
  p_pedido_id uuid,
  p_razon     text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_origen pedidos;
  v_nuevo_id uuid;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede clonar pedidos';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para clonar pedido';
  END IF;

  SELECT * INTO v_origen FROM pedidos WHERE id = p_pedido_id;
  IF v_origen.id IS NULL THEN
    RAISE EXCEPTION 'pedido % no existe', p_pedido_id;
  END IF;

  INSERT INTO pedidos (
    pedido_ref, id_consecutivo, cliente_id, empresa, zona, origen, destino, fuente,
    motivo_viaje, prioridad, fecha_cargue, fecha_entrega,
    peso_kg, tipo_mercancia, contenedores, cajas, bidones, canecas, unidades_sueltas,
    valor_mercancia, valor_factura, tipo_vehiculo,
    flete, standby, candado, escolta, itr, cargue_descargue,
    cliente_nombre, contacto_nombre, contacto_tel, direccion, horario, llamar_antes,
    observaciones, vendedor, jefe_zona, coordinador, placa, proveedor,
    estado, revisado_at, revision_notas,
    raw_payload
  ) VALUES (
    v_origen.pedido_ref, v_origen.id_consecutivo, v_origen.cliente_id, v_origen.empresa,
    v_origen.zona, v_origen.origen, v_origen.destino, v_origen.fuente,
    v_origen.motivo_viaje, v_origen.prioridad, v_origen.fecha_cargue, v_origen.fecha_entrega,
    v_origen.peso_kg, v_origen.tipo_mercancia,
    v_origen.contenedores, v_origen.cajas, v_origen.bidones, v_origen.canecas, v_origen.unidades_sueltas,
    v_origen.valor_mercancia, v_origen.valor_factura, v_origen.tipo_vehiculo,
    v_origen.flete, v_origen.standby, v_origen.candado, v_origen.escolta, v_origen.itr, v_origen.cargue_descargue,
    v_origen.cliente_nombre, v_origen.contacto_nombre, v_origen.contacto_tel,
    v_origen.direccion, v_origen.horario, v_origen.llamar_antes,
    v_origen.observaciones, v_origen.vendedor, v_origen.jefe_zona, v_origen.coordinador,
    v_origen.placa, v_origen.proveedor,
    'sin_consolidar', now(),
    'CLON de ' || p_pedido_id::text || ': ' || p_razon,
    jsonb_build_object('clon_de', p_pedido_id::text, 'razon', p_razon)::text
  ) RETURNING id INTO v_nuevo_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'clonar_pedido', 'pedido', v_nuevo_id,
    jsonb_build_object(
      'pedido_origen', p_pedido_id,
      'pedido_ref', v_origen.pedido_ref,
      'razon', p_razon
    ));

  RETURN v_nuevo_id;
END;
$$;

COMMIT;

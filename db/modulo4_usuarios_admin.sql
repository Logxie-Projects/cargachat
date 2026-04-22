-- ============================================================
-- Módulo 4 — Administración de usuarios (acciones_operador CHECK)
--
-- Extiende `acciones_operador.accion` con las 4 acciones que emite
-- la Edge Function `admin_user`:
--   · usuario_crear
--   · usuario_reset_password
--   · usuario_toggle_active
--   · usuario_eliminar
--
-- También agrega `usuario` al CHECK de entidad_tipo.
--
-- Idempotente. Se puede correr varias veces.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Extender accion CHECK (preserva acciones previas)
-- ------------------------------------------------------------
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.acciones_operador'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%accion%'
      AND pg_get_constraintdef(oid) NOT ILIKE '%entidad_tipo%' LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_accion_check CHECK (accion IN (
    -- Ciclo de viaje
    'consolidar','agregar_pedido','quitar_pedido','desconsolidar',
    'ajustar_precio','publicar','invitar','asignar_directo',
    'adjudicar','cancelar','reasignar','reabrir',
    -- Sync
    'sync_viajes','sync_pedidos','sync_seguimiento',
    'run_linkers','cleanup_ghosts',
    -- Revisión pedidos
    'revisar_pedido','desmarcar_revision',
    -- Cierre
    'cerrar','cerrar_batch','reabrir_cierre',
    -- Admin pedidos
    'cancelar_pedidos_batch','resetear_pedidos_batch','clonar_pedido',
    'editar_pedido','cambiar_estado_pedido','eliminar_pedido',
    -- Tracking
    'asociar_viaje','desasociar_viaje','reintentar_entrega',
    'marcar_salida_cargue','marcar_llegada_cargue',
    'marcar_llegada_descargue','marcar_salida_descargue',
    'subir_cumplido','crear_factura','marcar_factura_pagada',
    -- Scenarios
    'scenario_crear','scenario_agregar_pedido','scenario_quitar_pedido',
    'scenario_descartar','scenario_promover','scenario_limpiar',
    -- Flota
    'flota_conductor_crear','flota_conductor_editar','flota_conductor_desactivar',
    'flota_vehiculo_crear','flota_vehiculo_editar','flota_vehiculo_desactivar',
    'flota_doc_subir','flota_doc_eliminar',
    -- Usuarios (NUEVO 2026-04-23)
    'usuario_crear','usuario_reset_password','usuario_toggle_active','usuario_eliminar'
  ));

-- ------------------------------------------------------------
-- 2. Extender entidad_tipo CHECK
-- ------------------------------------------------------------
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.acciones_operador'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%entidad_tipo%' LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_entidad_tipo_check
  CHECK (entidad_tipo IN (
    'viaje','pedido','oferta','scenario',
    'conductor','vehiculo','doc_flota',
    'usuario'                                       -- NUEVO 2026-04-23
  ));

COMMIT;

-- ============================================================
-- Verificación post-deploy:
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conrelid='public.acciones_operador'::regclass AND contype='c';
-- ============================================================

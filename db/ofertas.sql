-- ============================================
-- TABLA DE OFERTAS — Subasta de viajes
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- Crear tabla
create table if not exists ofertas (
  id          uuid default gen_random_uuid() primary key,
  viaje_rt    text not null,                    -- RT_TOTAL del viaje (lo conecta con el Sheet)
  usuario_id  uuid not null references auth.users(id),
  nombre      text not null,                    -- nombre del transportador (de perfiles)
  empresa     text,                             -- empresa del transportador
  telefono    text,                             -- teléfono de contacto
  precio_oferta numeric not null,               -- precio ofertado en COP
  comentario  text,                             -- nota opcional del transportador
  estado      text default 'activa' check (estado in ('activa','aceptada','rechazada','cancelada')),
  created_at  timestamptz default now()
);

-- Índices para consultas rápidas
create index if not exists idx_ofertas_viaje on ofertas(viaje_rt);
create index if not exists idx_ofertas_usuario on ofertas(usuario_id);

-- RLS (Row Level Security) — proteger los datos
alter table ofertas enable row level security;

-- Cualquiera autenticado puede ver el CONTEO de ofertas por viaje (no los detalles)
create policy "Ver conteo ofertas" on ofertas
  for select using (auth.role() = 'authenticated');

-- Solo el transportador puede crear su propia oferta
create policy "Crear oferta propia" on ofertas
  for insert with check (auth.uid() = usuario_id);

-- Solo el transportador puede cancelar su propia oferta
create policy "Cancelar oferta propia" on ofertas
  for update using (auth.uid() = usuario_id)
  with check (estado = 'cancelada');

-- Evitar ofertas duplicadas: un usuario solo puede tener una oferta activa por viaje
create unique index if not exists idx_ofertas_unica
  on ofertas(viaje_rt, usuario_id) where (estado = 'activa');

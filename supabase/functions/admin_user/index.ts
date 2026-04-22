// ============================================================
// Edge Function: admin_user
// Propósito: CRUD de cuentas de usuario desde control.html tab Catálogo > Usuarios.
//   · Gate server-side: solo logxie_staff (valida JWT del caller contra perfiles).
//   · Usa service_role para acciones admin en auth.users (no expuesto al cliente).
//   · Log a acciones_operador (audit trail).
//
// Acciones soportadas:
//   list_users          → {} → {users: [...]}
//   create_user         → {email, nombre?, telefono?, tipo, transportadora_id?, rol_transportadora?}
//                         → {user_id, password, email}
//   reset_password      → {user_id} → {password}
//   toggle_active       → {user_id, activar:bool} → {estado}
//   delete_user         → {user_id} → {ok:true}
//   update_rol          → {user_id, rol_transportadora} → {rol_transportadora}
//
// Deploy: Dashboard Supabase → Edge Functions → New → paste this file.
// Requiere env vars:
//   SUPABASE_URL          (auto-set por Supabase)
//   SUPABASE_ANON_KEY     (auto-set)
//   SUPABASE_SERVICE_ROLE_KEY (auto-set)
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ─────────── Helpers ───────────

function genPassword(): string {
  // Netfleet-XXXXXX — sin chars ambiguos (0/O/1/l/I)
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  let out = "Netfleet-";
  const arr = new Uint32Array(6);
  crypto.getRandomValues(arr);
  for (let i = 0; i < 6; i++) out += chars[arr[i] % chars.length];
  return out;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function bad(msg: string, status = 400): Response {
  return json({ error: msg }, status);
}

// ─────────── Handler ───────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return bad("POST only", 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!SUPABASE_URL || !SERVICE_ROLE || !ANON_KEY) {
    return bad("Missing env vars on Edge Function", 500);
  }

  // 1) Gate: extraer JWT del caller y validar que sea logxie_staff aprobado
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return bad("Missing bearer token", 401);
  const token = authHeader.substring(7);

  // Service role para todo: validar el token + leer perfiles.
  // admin.auth.getUser(token) soporta JWTs ES256 (nuevo formato Supabase) —
  // a diferencia de callerClient.auth.getUser() con anon key.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) {
    return bad(`Invalid token: ${userErr?.message || "no user"}`, 401);
  }

  const callerId = userData.user.id;

  const { data: callerProfile, error: profErr } = await admin
    .from("perfiles")
    .select("tipo, estado")
    .eq("id", callerId)
    .single();

  if (profErr || !callerProfile) return bad("Caller profile not found", 403);
  if (callerProfile.tipo !== "logxie_staff" || callerProfile.estado !== "aprobado") {
    return bad("Forbidden — logxie_staff required", 403);
  }

  // 2) Parse body y dispatch
  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON body");
  }

  const action = body.action as string;
  if (!action) return bad("Missing action");

  try {
    switch (action) {
      case "list_users":      return await handleList(admin);
      case "create_user":     return await handleCreate(admin, callerId, body);
      case "reset_password":  return await handleReset(admin, callerId, body);
      case "toggle_active":   return await handleToggle(admin, callerId, body);
      case "delete_user":     return await handleDelete(admin, callerId, body);
      case "update_rol":      return await handleUpdateRol(admin, callerId, body);
      default:                return bad(`Unknown action: ${action}`);
    }
  } catch (e) {
    console.error("[admin_user]", action, e);
    return bad(String((e as Error).message || e), 500);
  }
});

// ─────────── Actions ───────────

async function handleList(admin: any): Response {
  // Traer perfiles + nombre de transportadora (si aplica) + last_sign_in_at de auth.users
  const { data: perfiles, error: e1 } = await admin
    .from("perfiles")
    .select("id, email, nombre, telefono, tipo, estado, transportadora_id, rol_transportadora, created_at")
    .order("created_at", { ascending: false });
  if (e1) throw e1;

  const { data: transps, error: e2 } = await admin
    .from("transportadoras")
    .select("id, nombre");
  if (e2) throw e2;

  const transpMap = new Map<string, string>();
  for (const t of transps || []) transpMap.set(t.id, t.nombre);

  // Listar todos los users de auth para obtener last_sign_in_at (paginado, max 1000 cuentas por ahora)
  const { data: authList, error: e3 } = await admin.auth.admin.listUsers({ perPage: 1000 });
  if (e3) throw e3;

  const lastSignMap = new Map<string, string | null>();
  for (const u of authList?.users || []) lastSignMap.set(u.id, u.last_sign_in_at ?? null);

  const users = (perfiles || []).map((p: any) => ({
    id: p.id,
    email: p.email,
    nombre: p.nombre,
    telefono: p.telefono,
    tipo: p.tipo,
    estado: p.estado,
    transportadora_id: p.transportadora_id,
    transportadora_nombre: p.transportadora_id ? transpMap.get(p.transportadora_id) || null : null,
    rol_transportadora: p.rol_transportadora,
    last_sign_in_at: lastSignMap.get(p.id) ?? null,
    created_at: p.created_at,
  }));

  return json({ users });
}

async function handleCreate(admin: any, callerId: string, body: any): Response {
  const email = String(body.email || "").trim().toLowerCase();
  const nombre = String(body.nombre || "").trim() || null;
  const telefono = String(body.telefono || "").trim() || null;
  const tipo = String(body.tipo || "").trim();
  const transportadora_id = body.transportadora_id || null;
  const rol_raw = body.rol_transportadora ? String(body.rol_transportadora).trim() : null;
  const rol_transportadora =
    rol_raw && ["comercial", "operativo", "facturacion"].includes(rol_raw) ? rol_raw : null;

  if (!email) return bad("email requerido");
  if (!["transportador", "logxie_staff"].includes(tipo)) {
    return bad("tipo debe ser transportador o logxie_staff");
  }
  if (tipo === "transportador" && !transportadora_id) {
    return bad("transportadora_id requerido cuando tipo=transportador");
  }

  const password = genPassword();

  // 1) Crear user en auth
  const { data: created, error: e1 } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { nombre, telefono },
  });
  if (e1) throw e1;
  const newId = created?.user?.id;
  if (!newId) throw new Error("auth.createUser no devolvió user.id");

  // 2) handle_new_user trigger creó la fila con tipo=transportador por default.
  //    UPDATE para fijar tipo correcto + estado=aprobado + transportadora_id.
  const empresaNombre = transportadora_id
    ? (await admin.from("transportadoras").select("nombre").eq("id", transportadora_id).single()).data?.nombre
    : null;

  const { error: e2 } = await admin
    .from("perfiles")
    .update({
      tipo,
      estado: "aprobado",
      transportadora_id: transportadora_id,
      empresa: empresaNombre,
      nombre,
      telefono,
      // rol_transportadora solo tiene sentido si tipo=transportador
      rol_transportadora: tipo === "transportador" ? rol_transportadora : null,
    })
    .eq("id", newId);
  if (e2) throw e2;

  // 3) Audit
  await admin.from("acciones_operador").insert({
    user_id: callerId,
    accion: "usuario_crear",
    entidad_tipo: "usuario",
    entidad_id: newId,
    metadata: { email, tipo, transportadora_id, nombre, rol_transportadora },
  });

  return json({ user_id: newId, email, password });
}

async function handleUpdateRol(admin: any, callerId: string, body: any): Response {
  const user_id = String(body.user_id || "");
  const rol_raw = body.rol_transportadora ? String(body.rol_transportadora).trim() : null;
  const rol =
    rol_raw && ["comercial", "operativo", "facturacion"].includes(rol_raw) ? rol_raw : null;

  if (!user_id) return bad("user_id requerido");

  const { error } = await admin
    .from("perfiles")
    .update({ rol_transportadora: rol })
    .eq("id", user_id);
  if (error) throw error;

  await admin.from("acciones_operador").insert({
    user_id: callerId,
    accion: "usuario_toggle_active",  // reutilizamos la acción existente (evita migration nueva)
    entidad_tipo: "usuario",
    entidad_id: user_id,
    metadata: { cambio: "rol_transportadora", nuevo_rol: rol },
  });

  return json({ rol_transportadora: rol });
}

async function handleReset(admin: any, callerId: string, body: any): Response {
  const user_id = String(body.user_id || "");
  if (!user_id) return bad("user_id requerido");

  const password = genPassword();
  const { error } = await admin.auth.admin.updateUserById(user_id, { password });
  if (error) throw error;

  await admin.from("acciones_operador").insert({
    user_id: callerId,
    accion: "usuario_reset_password",
    entidad_tipo: "usuario",
    entidad_id: user_id,
    metadata: { at: new Date().toISOString() },
  });

  return json({ password });
}

async function handleToggle(admin: any, callerId: string, body: any): Response {
  const user_id = String(body.user_id || "");
  const activar = !!body.activar;
  if (!user_id) return bad("user_id requerido");

  const nuevoEstado = activar ? "aprobado" : "rechazado";
  const { error } = await admin
    .from("perfiles")
    .update({ estado: nuevoEstado })
    .eq("id", user_id);
  if (error) throw error;

  await admin.from("acciones_operador").insert({
    user_id: callerId,
    accion: "usuario_toggle_active",
    entidad_tipo: "usuario",
    entidad_id: user_id,
    metadata: { nuevo_estado: nuevoEstado },
  });

  return json({ estado: nuevoEstado });
}

async function handleDelete(admin: any, callerId: string, body: any): Response {
  const user_id = String(body.user_id || "");
  if (!user_id) return bad("user_id requerido");

  // Snapshot antes de borrar (para audit)
  const { data: snap } = await admin
    .from("perfiles")
    .select("email, nombre, tipo, transportadora_id")
    .eq("id", user_id)
    .single();

  // Audit ANTES del delete (el perfil se borra por cascade)
  await admin.from("acciones_operador").insert({
    user_id: callerId,
    accion: "usuario_eliminar",
    entidad_tipo: "usuario",
    entidad_id: user_id,
    metadata: { snapshot: snap || null },
  });

  const { error } = await admin.auth.admin.deleteUser(user_id);
  if (error) throw error;

  return json({ ok: true });
}

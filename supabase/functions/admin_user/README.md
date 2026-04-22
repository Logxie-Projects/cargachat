# Edge Function: `admin_user`

Gestión de cuentas de usuario (transportadoras + staff) desde `control.html` → Catálogo → Usuarios. Usa `service_role` para operaciones admin en `auth.users` (no expuesto al cliente).

## Pre-requisitos

1. ✅ Migration `db/modulo4_usuarios_admin.sql` aplicada (extiende `acciones_operador.accion` CHECK).
2. ✅ `perfiles.transportadora_id` FK existe (creado en sesión Flota).
3. ✅ RLS aislamiento por transportadora endurecido (commit `67383c1`).

## Deploy — Dashboard Supabase (copy-paste)

1. Ir a [Dashboard → Edge Functions](https://supabase.com/dashboard/project/pzouapqnvllaaqnmnlbs/functions).
2. Botón **"Deploy a new function"**.
3. Nombre: `admin_user`.
4. Pegar contenido de [`index.ts`](./index.ts) en el editor.
5. Click **Deploy** — tarda ~30s.
6. Verificar que las env vars estén seteadas (auto-inyectadas por Supabase):
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`

## Deploy — Supabase CLI (futuro, si se instala)

```bash
supabase functions deploy admin_user --project-ref pzouapqnvllaaqnmnlbs
```

## Smoke test con curl

Reemplazá `<JWT>` por el `access_token` de una sesión activa de `bernardoaristizabal@logxie.com` (logueado en control.html → `localStorage.getItem('sb-pzouapqnvllaaqnmnlbs-auth-token')` → `access_token`).

```bash
# List users (debe devolver array con al menos los 3 perfiles existentes)
curl -X POST https://pzouapqnvllaaqnmnlbs.supabase.co/functions/v1/admin_user \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"action":"list_users"}'

# Create user test (transportadora)
curl -X POST https://pzouapqnvllaaqnmnlbs.supabase.co/functions/v1/admin_user \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "action":"create_user",
    "email":"test-entrapetrol@netfleet.app",
    "nombre":"Test Entrapetrol",
    "tipo":"transportador",
    "transportadora_id":"<UUID_DE_ENTRAPETROL>"
  }'
# Response: {"user_id":"...","email":"...","password":"Netfleet-XXXXXX"}

# Reset password
curl -X POST https://pzouapqnvllaaqnmnlbs.supabase.co/functions/v1/admin_user \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"action":"reset_password","user_id":"<UUID>"}'

# Toggle active (suspender)
curl -X POST https://pzouapqnvllaaqnmnlbs.supabase.co/functions/v1/admin_user \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"action":"toggle_active","user_id":"<UUID>","activar":false}'

# Delete user
curl -X POST https://pzouapqnvllaaqnmnlbs.supabase.co/functions/v1/admin_user \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"action":"delete_user","user_id":"<UUID>"}'
```

## Gate de seguridad

La función valida en orden:
1. `Authorization: Bearer <jwt>` presente.
2. JWT válido → `supabase.auth.getUser()` resuelve el `user_id`.
3. `perfiles.tipo = 'logxie_staff'` y `perfiles.estado = 'aprobado'` para ese `user_id`.

Si cualquier paso falla → `401` / `403`. `service_role` se usa SOLO después del gate — nunca expuesto al cliente.

## Acciones y estructura del payload

| Acción | Payload (además de `action`) | Respuesta |
|---|---|---|
| `list_users` | — | `{users: [...]}` |
| `create_user` | `email, nombre?, telefono?, tipo ('transportador'\|'logxie_staff'), transportadora_id? (requerido si tipo=transportador)` | `{user_id, email, password}` |
| `reset_password` | `user_id` | `{password}` |
| `toggle_active` | `user_id, activar: bool` | `{estado}` |
| `delete_user` | `user_id` | `{ok: true}` |

## Audit trail

Todas las acciones (excepto `list_users`) se loguean en `acciones_operador`:
- `accion`: `usuario_crear` / `usuario_reset_password` / `usuario_toggle_active` / `usuario_eliminar`
- `entidad_tipo`: `usuario`
- `entidad_id`: UUID del usuario target
- `metadata`: snapshot relevante de la acción
- `user_id`: UUID del staff que ejecutó la acción

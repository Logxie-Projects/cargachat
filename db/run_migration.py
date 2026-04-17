#!/usr/bin/env python3
"""
Ejecuta los SQL del Módulo 2 contra Supabase en orden.

Uso:
  export DATABASE_URL="postgresql://postgres.pzouapqnvllaaqnmnlbs:[PWD]@aws-X-us-east-1.pooler.supabase.com:5432/postgres"
  python db/run_migration.py

La connection string sale de:
  Supabase Dashboard → Project Settings → Database
  → Connection string → "Session pooler" → URI

Ejecuta en orden:
  1. Schemas: clientes.sql, viajes.sql, pedidos.sql
  2. Dumps: migrate_viajes_chunk_{01..03}.sql (1281 viajes)
  3. Dumps: migrate_pedidos_chunk_{01..06}.sql (3764 pedidos)

Cada archivo en su propia transacción. Si uno falla, stop.
Los schemas usan CREATE TABLE (no IF NOT EXISTS) — re-correr falla.
Los migrates usan INSERT sin ON CONFLICT — re-correr duplica.
"""

import os
import sys
import time
from pathlib import Path

try:
    import psycopg
    PSYCOPG_VERSION = 3
except ImportError:
    try:
        import psycopg2 as psycopg
        PSYCOPG_VERSION = 2
    except ImportError:
        print("ERROR: falta psycopg. Instalar con:")
        print("  pip install psycopg[binary]")
        print("  (o psycopg2-binary si preferis psycopg2)")
        sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent

FILES = [
    "db/clientes.sql",
    "db/viajes.sql",
    "db/pedidos.sql",
    "db/migrate_viajes_chunk_01.sql",
    "db/migrate_viajes_chunk_02.sql",
    "db/migrate_viajes_chunk_03.sql",
    "db/migrate_pedidos_chunk_01.sql",
    "db/migrate_pedidos_chunk_02.sql",
    "db/migrate_pedidos_chunk_03.sql",
    "db/migrate_pedidos_chunk_04.sql",
    "db/migrate_pedidos_chunk_05.sql",
    "db/migrate_pedidos_chunk_06.sql",
]


def connect(db_url: str):
    if PSYCOPG_VERSION == 3:
        return psycopg.connect(db_url, autocommit=False)
    return psycopg.connect(db_url)


def run_file(conn, path: Path) -> float:
    sql = path.read_text(encoding="utf-8")
    start = time.time()
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()
    return time.time() - start


def verify(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM clientes")
        clientes = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM viajes_consolidados")
        viajes = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM pedidos")
        pedidos = cur.fetchone()[0]
    return clientes, viajes, pedidos


def main():
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("ERROR: exporta DATABASE_URL antes de correr.")
        print('  $env:DATABASE_URL="postgresql://postgres.XXX:PWD@host:5432/postgres"  (PowerShell)')
        print('  export DATABASE_URL="postgresql://..."                                 (bash)')
        sys.exit(1)

    # Ocultar password al loggear
    masked = db_url
    if "@" in db_url and ":" in db_url.split("@")[0]:
        head, tail = db_url.rsplit("@", 1)
        user_pwd = head.rsplit(":", 1)
        masked = f"{user_pwd[0]}:****@{tail}"
    print(f"→ Conectando: {masked}")

    conn = connect(db_url)
    print(f"  ✓ Conexión OK (psycopg v{PSYCOPG_VERSION})\n")

    for rel_path in FILES:
        path = REPO_ROOT / rel_path
        if not path.exists():
            print(f"  ⚠  SKIP (no existe): {rel_path}")
            continue

        size_kb = path.stat().st_size // 1024
        print(f"→ {rel_path} ({size_kb} KB)")

        try:
            elapsed = run_file(conn, path)
            print(f"  ✓ OK en {elapsed:.1f}s")
        except Exception as e:
            conn.rollback()
            print(f"  ✗ FAIL: {type(e).__name__}: {e}")
            print(f"\nDetenido en {rel_path}. Los archivos anteriores quedaron commiteados.")
            sys.exit(1)

    print("\n→ Verificación final")
    try:
        clientes, viajes, pedidos = verify(conn)
        print(f"  clientes:            {clientes}")
        print(f"  viajes_consolidados: {viajes} (esperado: 1281)")
        print(f"  pedidos:             {pedidos} (esperado: 3764)")
        ok = viajes == 1281 and pedidos == 3764
        print(f"\n{'✓ Migración completa.' if ok else '⚠  Conteos no coinciden.'}")
    except Exception as e:
        print(f"  ✗ verificación falló: {e}")

    conn.close()


if __name__ == "__main__":
    main()

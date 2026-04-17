#!/usr/bin/env python3
"""
Ejecuta SQL contra Supabase — 3 modos.

Uso:
  # 1. Inicial (primera vez): crea schemas + carga dumps + backfill + link
  python db/run_migration.py

  # 2. Refresh (re-migraciones semanales): preserva clientes,
  #    TRUNCATE viajes + pedidos, recarga dumps frescos, backfill + link
  python db/run_migration.py --refresh

  # 3. Archivo suelto (debug, queries ad-hoc)
  python db/run_migration.py --file db/verify.sql

Requiere env var DATABASE_URL (Supabase Dashboard → Database → Session pooler).

Flujo de datos:
  Google Sheet Base_inicio-def    → db/migrate_pedidos.sql  → tabla pedidos
  Google Sheet ASIGNADOS          → db/migrate_viajes.sql   → tabla viajes_consolidados
  (después) post_migration.sql    → backfill pedidos.cliente_id desde empresa
  (después) link_pedidos_viajes   → backfill pedidos.viaje_id desde consecutivos

Modo --refresh asume que los dumps (db/migrate_*.sql) se regeneraron desde
el Sheet actual antes de correr. Diseñado para ejecutarse varias veces por
semana mientras la base crece y Netfleet reemplaza el Apps Script.
"""

import argparse
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

SCHEMAS = [
    "db/clientes.sql",
    "db/viajes.sql",
    "db/pedidos.sql",
]

DUMPS = [
    "db/migrate_viajes.sql",
    "db/migrate_pedidos.sql",
]

POST = [
    "db/post_migration.sql",
    "db/link_pedidos_viajes.sql",
]

# Orden para migración inicial: schemas → dumps → post
FILES = SCHEMAS + DUMPS + POST

TRUNCATE_SQL = "TRUNCATE TABLE pedidos, viajes_consolidados RESTART IDENTITY CASCADE;"


def connect(db_url: str):
    if PSYCOPG_VERSION == 3:
        return psycopg.connect(db_url, autocommit=False)
    return psycopg.connect(db_url)


def run_file(conn, path: Path) -> float:
    sql = path.read_text(encoding="utf-8")
    start = time.time()
    with conn.cursor() as cur:
        cur.execute(sql)
        # Si el último statement es un SELECT, imprimir resultados
        if cur.description:
            rows = cur.fetchall()
            cols = [d[0] for d in cur.description]
            if rows:
                widths = [max(len(str(c)), max((len(str(r[i])) for r in rows), default=0)) for i, c in enumerate(cols)]
                print("  " + " | ".join(c.ljust(widths[i]) for i, c in enumerate(cols)))
                print("  " + "-+-".join("-" * w for w in widths))
                for r in rows:
                    print("  " + " | ".join(str(r[i]).ljust(widths[i]) for i in range(len(cols))))
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


def truncate_volatile(conn):
    """TRUNCATE viajes_consolidados + pedidos. Preserva clientes.
    También quita temporalmente NOT NULL en pedidos.cliente_id para permitir
    que los dumps re-inserten (no setean cliente_id). post_migration.sql
    lo restaura al final."""
    print(f"→ TRUNCATE pedidos + viajes_consolidados (preserva clientes)")
    with conn.cursor() as cur:
        cur.execute(TRUNCATE_SQL)
        cur.execute("ALTER TABLE pedidos ALTER COLUMN cliente_id DROP NOT NULL;")
    conn.commit()
    print("  ✓ OK\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", help="Ejecutar un solo archivo SQL")
    parser.add_argument("--refresh", action="store_true",
                        help="Re-migración: TRUNCATE pedidos+viajes, recarga dumps, backfill, link. No toca clientes ni schemas.")
    args = parser.parse_args()

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

    # Modo single-file
    if args.file:
        path = Path(args.file)
        if not path.is_absolute():
            path = REPO_ROOT / args.file
        if not path.exists():
            print(f"✗ Archivo no existe: {path}")
            sys.exit(1)
        size_kb = path.stat().st_size // 1024
        print(f"→ {args.file} ({size_kb} KB)")
        try:
            elapsed = run_file(conn, path)
            print(f"  ✓ OK en {elapsed:.1f}s")
        except Exception as e:
            conn.rollback()
            print(f"  ✗ FAIL: {type(e).__name__}: {e}")
            sys.exit(1)
        conn.close()
        return

    # Decidir lista de archivos según modo
    if args.refresh:
        print("→ Modo REFRESH: TRUNCATE + recarga dumps + backfill + link\n")
        try:
            truncate_volatile(conn)
        except Exception as e:
            conn.rollback()
            print(f"  ✗ TRUNCATE falló: {type(e).__name__}: {e}")
            print("  ¿Ya corriste los schemas? Si no, corré sin --refresh primero.")
            sys.exit(1)
        files_to_run = DUMPS + POST
    else:
        print("→ Modo INICIAL: schemas + dumps + backfill + link\n")
        files_to_run = FILES

    for rel_path in files_to_run:
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

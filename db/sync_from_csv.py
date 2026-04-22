#!/usr/bin/env python3
"""
Sync masivo desde CSV exportado de Google Sheets → Supabase vía RPC.

Uso:
  python db/sync_from_csv.py --viajes dumps/asignados.csv
  python db/sync_from_csv.py --pedidos dumps/base_inicio_def.csv
  python db/sync_from_csv.py --viajes dumps/asignados.csv --pedidos dumps/base_inicio_def.csv

Qué hace:
  1. Lee el CSV
  2. Mapea columnas del Sheet → formato canónico del payload JSONB
  3. Llama fn_sync_viajes_batch / fn_sync_pedidos_batch en batches de 500
  4. Imprime counters (insertados, actualizados, saltados, errores)

Requiere: DATABASE_URL (mismo que run_migration.py)
"""

import argparse
import csv
import json
import os
import sys
from datetime import datetime
from pathlib import Path

try:
    import psycopg
    PSYCOPG_VERSION = 3
except ImportError:
    import psycopg2 as psycopg
    PSYCOPG_VERSION = 2

BATCH_SIZE = 500

# ============================================================
# Mapping de columnas: ASIGNADOS Sheet → payload canónico
# (headers confirmados 2026-04-19)
# ============================================================
VIAJES_COLS = {
    'ID_CONSOLIDADO':            'viaje_ref',
    'FECHA_CONSOLIDACION':       'fecha_consolidacion',
    'PEDIDOS_INCLUIDOS':         'PEDIDOS_INCLUIDOS',  # passthrough al raw_payload para linker v2
    'ZONA_CONSOLIDADA':          'zona',
    'ORIGEN_CONSOLIDADO':        'origen',
    'DESTINO_CONSOLIDADO':       'destino',
    'KM_TOTAL':                  'km_total',
    'FLETE_TOTAL':               'flete_total',
    'ESTADO':                    'estado_sheet',
    'ESTADO ':                   'estado_sheet',   # header del Sheet tiene espacio
    'CANTIDAD_PEDIDOS':          'cantidad_pedidos',
    'EMPRESA_CONSOLIDADA':       'empresa',
    'CONSECUTIVOS_INCLUIDOS':    'consecutivos',
    'Proveedor':                 'proveedor',
    'PESO TRANSPORTADO (Kilos)': 'peso_kg',
    'CONTENEDORES':              'contenedores',
    'CAJAS':                     'cajas',
    'BIDONES':                   'bidones',
    'CANECAS':                   'canecas',
    'UNIDADES SUELTAS':          'unidades_sueltas',
    'VALOR DE LA MERCANCIA':     'valor_mercancia',
    'observaciones':             'observaciones',
    'fecha Carga':               'fecha_cargue',
    'Identificacion Conductor':  'conductor_id',
    'Nombre del conductor':      'conductor_nombre',
    'Placa del Vehiculo':        'placa',
    'Tipo Vehiculo':             'tipo_vehiculo',
    'Foto del Cargue':           'foto_cargue',
    'soporte de entrega':        'soporte_entrega',
    'Confirma Vehiculo':         'confirma_vehiculo',
}

# ============================================================
# Mapping Base_inicio-def → pedidos (headers confirmados 2026-04-19)
# ============================================================
PEDIDOS_COLS = {
    'ID_Inicio':                   'id_inicio',     # llave estable AppSheet (col A)
    'CONSECUTIVO IMP / LOG / CRM': 'pedido_ref',
    'ID_consecutivo':              'id_consecutivo',
    'EMPRESA':                     'empresa',
    'FECHA ESTIMADA CARGUE':       'fecha_cargue',
    'FECHA REQUERIDA DE ENTREGA':  'fecha_entrega',
    'ZONA':                        'zona',
    'ORIGEN':                      'origen',
    'DESTINO':                     'destino',
    'TIPO VEHICULO':               'tipo_vehiculo',
    'FLETE':                       'flete',
    'STANDBY':                     'standby',
    'CANDADO':                     'candado',
    'ESCOLTA':                     'escolta',
    'ITR':                         'itr',
    'CARGUE / DESCARGUE':          'cargue_descargue',
    'VALOR DE LA FACTURA':         'valor_factura',
    'PRODUCTOS / REMISION':        'tipo_mercancia',
    'PESO TRANSPORTADO (Kilos)':   'peso_kg',
    'CONTENEDORES':                'contenedores',
    'CAJAS':                       'cajas',
    'BIDONES':                     'bidones',
    'CANECAS':                     'canecas',
    'UNIDADES SUELTAS':            'unidades_sueltas',
    'VALOR DE LA MERCANCIA':       'valor_mercancia',
    'PROVEEDOR':                   'proveedor',
    'ESTADO DEL VIAJE':            'estado_sheet',
    'Nro FACTURA PROVEEDOR':       'nro_factura_proveedor',
    'MOTIVO DEL VIAJE':            'motivo_viaje',
    'JEFE DE ZONA':                'jefe_zona',
    'VENDEDOR QUE SOLICITA':       'vendedor',
    'COORDINADOR DEL SERVICIO':    'coordinador',
    'CLIENTE':                     'cliente_nombre',
    'WHATSAPP':                    'contacto_tel',
    'PLACA':                       'placa',
    'PRIORIDAD':                   'prioridad',
    'Observaciones':               'observaciones',
    'Soportes_1':                  'soporte_1',
    'Soportes_2':                  'soporte_2',
    'Soportes_3':                  'soporte_3',
    'Dirrecion':                   'direccion',
    'bodega email':                'bodega_email',
    'Confirmar  Vehiculo':         'confirma_vehiculo',  # Sheet tiene 2 espacios
    'Confirmar Vehiculo':          'confirma_vehiculo',
    # Ignorados: ID_Inicio (interno AppSheet), KM (no en schema), SELECCIONAR, Fecha Creacion, soportes (columna extra)
}


DATE_FORMATS = [
    '%Y-%m-%dT%H:%M:%S',    # ISO
    '%Y-%m-%d %H:%M:%S',
    '%Y-%m-%d',
    # LATAM primero — el Sheet de Bernardo usa dd/mm/yyyy. Si US va primero,
    # fechas como "9/4/2026" se parsean como "4 septiembre 2026" (futuro) en vez
    # de "9 abril 2026". Para pares donde día y mes son ambiguos (ambos ≤12),
    # LATAM primero evita swap silencioso.
    '%d/%m/%Y %H:%M:%S',    # LATAM con hora
    '%d/%m/%Y',             # LATAM sin hora
    '%m/%d/%Y %H:%M:%S',    # US con hora (fallback)
    '%m/%d/%Y',             # US sin hora (fallback)
]

DATE_KEYS = ('fecha_cargue','fecha_entrega','fecha_consolidacion')
NUM_KEYS  = ('km_total','flete_total','peso_kg','valor_mercancia','valor_factura',
             'cantidad_pedidos','contenedores','cajas','bidones','canecas',
             'unidades_sueltas','flete','standby','candado','escolta','itr','otros')
BOOL_KEYS = ('llamar_antes',)


def parse_date(s):
    """Intenta varios formatos. Devuelve ISO string o None."""
    s = s.strip()
    if not s: return None
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt).isoformat()
        except ValueError:
            continue
    return None


def parse_value(val, key):
    """Normalizar valores del CSV."""
    if val is None or val == '':
        return None
    s = val.strip()
    if s == '' or s.upper() == 'NULL':
        return None
    if key in DATE_KEYS:
        return parse_date(s)
    if key in NUM_KEYS:
        s = s.replace('$','').replace(',','').strip()
        try:
            return float(s) if '.' in s else int(s)
        except ValueError:
            return None
    if key in BOOL_KEYS:
        return s.lower() in ('true','1','sí','si','yes','y')
    return s


def csv_to_payload(csv_path, col_map):
    """Leer CSV y convertir cada row a dict canónico.
    Normaliza headers (strip whitespace) — Sheets exporta con espacios inconsistentes.
    """
    path = Path(csv_path)
    if not path.exists():
        print(f"✗ archivo no existe: {csv_path}")
        sys.exit(1)

    # Normalizar también las claves del map (trim)
    norm_map = {k.strip(): v for k, v in col_map.items()}

    # Probar utf-8-sig primero, fallback a cp1252 (Excel en Windows)
    encodings_to_try = ['utf-8-sig', 'cp1252', 'latin-1']
    file_contents = None
    encoding_used = None
    for enc in encodings_to_try:
        try:
            with open(path, encoding=enc) as f:
                file_contents = f.read()
                encoding_used = enc
                break
        except UnicodeDecodeError:
            continue
    if file_contents is None:
        print(f"✗ No se pudo decodificar {csv_path} con ninguna encoding")
        sys.exit(1)
    if encoding_used != 'utf-8-sig':
        print(f"  ⓘ CSV en encoding {encoding_used} (no UTF-8)")

    import io
    # Detectar delimitador (Excel español usa ';', Google Sheets usa ',')
    sample = file_contents[:4096]
    first_line = sample.split('\n')[0]
    delim = ';' if first_line.count(';') > first_line.count(',') else ','
    if delim != ',':
        print(f"  ⓘ Delimitador detectado: '{delim}'")

    rows_out = []
    unknown_headers = set()
    with io.StringIO(file_contents) as f:
        reader = csv.DictReader(f, delimiter=delim)
        # Normalizar fieldnames (trim whitespace)
        original_fields = reader.fieldnames or []
        reader.fieldnames = [h.strip() for h in original_fields]

        for h in reader.fieldnames:
            if h not in norm_map and h not in ('ID_Inicio','ID_CONSOLIDADO',):
                unknown_headers.add(h)

        for i, raw_row in enumerate(reader, start=2):
            row = {}
            for sheet_col, canonical_key in norm_map.items():
                if sheet_col not in raw_row:
                    continue
                if canonical_key is None:
                    continue
                val = parse_value(raw_row[sheet_col], canonical_key)
                if val is not None:
                    row[canonical_key] = val
            if 'viaje_ref' in row or 'pedido_ref' in row:
                rows_out.append(row)
    if unknown_headers:
        print(f"  ⚠ Headers sin mapear (se ignoran): {sorted(unknown_headers)}")
    return rows_out


def call_sync(conn, function_name, payload_batch):
    """Ejecuta una RPC en batch."""
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT {function_name}(%s::jsonb)",
            (json.dumps(payload_batch),)
        )
        (result,) = cur.fetchone()
    conn.commit()
    return result


def run_sync(conn, rows, function_name):
    total = len(rows)
    print(f"\n→ {function_name}: {total} rows, batches de {BATCH_SIZE}")
    agg = {'insertados': 0, 'actualizados': 0, 'errores': 0}
    other_counters = {}
    for i in range(0, total, BATCH_SIZE):
        batch = rows[i:i+BATCH_SIZE]
        try:
            result = call_sync(conn, function_name, batch)
        except Exception as e:
            print(f"  ✗ batch {i}-{i+len(batch)} FAIL: {e}")
            conn.rollback()
            continue
        for k, v in result.items():
            if k in agg:
                agg[k] += v or 0
            elif isinstance(v, int):
                other_counters[k] = other_counters.get(k, 0) + v
        print(f"  ✓ batch {i+1}-{i+len(batch)} de {total} · ins={result.get('insertados',0)} upd={result.get('actualizados',0)} skip={sum(v for k,v in result.items() if k.startswith('saltados') and isinstance(v,int))} err={result.get('errores',0)}")

    print(f"\n═══ TOTAL {function_name} ═══")
    for k, v in agg.items(): print(f"  {k}: {v}")
    for k, v in other_counters.items(): print(f"  {k}: {v}")
    return agg


def truncate_all(conn):
    """Limpia viajes + pedidos (CASCADE también limpia ofertas, invitaciones).
    NO toca: clientes, transportadoras, perfiles, acciones_operador.
    """
    print("\n⚠  TRUNCATE CASCADE: viajes_consolidados + pedidos (incluye ofertas/invitaciones)")
    print("    clientes/transportadoras/perfiles/acciones_operador NO se tocan")
    resp = input("    Confirmá escribiendo 'si': ").strip().lower()
    if resp != 'si':
        print("    Abortado.")
        sys.exit(1)
    with conn.cursor() as cur:
        cur.execute("ALTER TABLE pedidos ALTER COLUMN cliente_id DROP NOT NULL;")
        cur.execute("TRUNCATE TABLE pedidos, viajes_consolidados RESTART IDENTITY CASCADE;")
    conn.commit()
    print("    ✓ TRUNCATE OK · cliente_id temporalmente nullable")


def run_sql_file(conn, path):
    p = Path(path)
    if not p.exists():
        print(f"  ⚠ SKIP no existe: {path}")
        return
    print(f"→ Ejecutando {path}")
    with conn.cursor() as cur:
        cur.execute(p.read_text(encoding='utf-8'))
        if cur.description:
            try:
                rows = cur.fetchall()
                if rows:
                    for r in rows: print(f"    {r}")
            except Exception: pass
    conn.commit()
    print(f"  ✓ OK")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--viajes', help='CSV de ASIGNADOS')
    parser.add_argument('--pedidos', help='CSV de Base_inicio-def')
    parser.add_argument('--truncate', action='store_true',
                        help='Borra viajes+pedidos antes de migrar (migración limpia)')
    parser.add_argument('--skip-post', action='store_true',
                        help='No correr post_migration.sql ni linker después del sync')
    args = parser.parse_args()

    if not args.viajes and not args.pedidos:
        parser.error('Especificá al menos uno: --viajes o --pedidos')

    db_url = os.environ.get('DATABASE_URL')
    if not db_url:
        print('ERROR: exportá DATABASE_URL antes de correr')
        sys.exit(1)

    print(f"→ Conectando…")
    conn = psycopg.connect(db_url, autocommit=False) if PSYCOPG_VERSION == 3 else psycopg.connect(db_url)
    print(f"  ✓ OK")

    # Pre-parsear ambos CSVs ANTES de truncar (si falla el parse, cancelamos sin daño)
    viajes_rows = []
    pedidos_rows = []
    if args.viajes:
        viajes_rows = csv_to_payload(args.viajes, VIAJES_COLS)
        print(f"→ CSV viajes parseado: {len(viajes_rows)} filas")
    if args.pedidos:
        pedidos_rows = csv_to_payload(args.pedidos, PEDIDOS_COLS)
        print(f"→ CSV pedidos parseado: {len(pedidos_rows)} filas")

    if args.truncate:
        truncate_all(conn)

    if viajes_rows:
        run_sync(conn, viajes_rows, 'fn_sync_viajes_batch')
    if pedidos_rows:
        run_sync(conn, pedidos_rows, 'fn_sync_pedidos_batch')

    if not args.skip_post:
        print("\n→ Post-migration: backfill cliente_id + restaurar NOT NULL")
        run_sql_file(conn, 'db/post_migration.sql')
        print("\n→ Linker v3: regex parser (aliases intra-token)")
        run_sql_file(conn, 'db/link_pedidos_viajes_v3.sql')
        print("\n→ Linker v4: pase substring (rescate BUSCARX-style)")
        run_sql_file(conn, 'db/link_pedidos_viajes_v4.sql')
        print("\n→ Linker v5: re-linkeo de pedidos reconsolidados (activos en viajes cancelados)")
        run_sql_file(conn, 'db/link_pedidos_viajes_v5.sql')

    conn.close()
    print("\n✓ DONE")


if __name__ == '__main__':
    main()

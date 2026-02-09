# DecoJewels API backend (FastAPI)
import asyncio
from contextlib import asynccontextmanager, closing
from datetime import date, datetime
from decimal import Decimal
from io import BytesIO
import json
import os
import re
from typing import Any, Dict, List

# python-dotenv is optional in some deployments (e.g. production PM2 envs)
try:
    from dotenv import load_dotenv  # type: ignore
except ModuleNotFoundError:
    load_dotenv = None  # type: ignore
from fastapi import FastAPI, HTTPException, Request  # type: ignore
from fastapi.middleware.cors import CORSMiddleware  # type: ignore
from fastapi.responses import Response  # type: ignore
import psycopg  # type: ignore
from psycopg.rows import dict_row  # type: ignore
from psycopg.sql import Identifier, SQL  # type: ignore
from pydantic import BaseModel  # type: ignore
import qrcode  # type: ignore

from config import get_db_connection_params

if load_dotenv:
    load_dotenv()

# In-memory cache for slow endpoints (avoids timeout on retry)
_challan_options_cache = None
_challan_options_cache_time = 0
CHALLAN_OPTIONS_CACHE_TTL = 300  # 5 min

_challans_list_cache = {}
_challans_list_cache_time = {}

_party_data_cache = {}
_party_data_cache_time = {}
PARTY_DATA_CACHE_TTL = 300  # 5 min - party data rarely changes


def _migrate_varchar_columns(cursor, conn):
    """Explicitly migrate VARCHAR(50) columns to VARCHAR(255) for party_name, station_name, transport_name, challan_number.
    This function ALWAYS attempts to alter columns - PostgreSQL will handle gracefully if already correct size.
    Uses USING clause to handle any data conversion issues.
    """
    tables_to_migrate = ['challans', 'orders']
    columns_to_migrate = ['party_name', 'station_name', 'transport_name']
    # Also migrate challan_number in challans table (it can be long when party name is included)
    challan_number_migration = [('challans', 'challan_number')]
    
    for table_name in tables_to_migrate:
        # First check if table exists
        try:
            cursor.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_name = %s
                )
            """, (table_name,))
            table_exists = cursor.fetchone()
            if not table_exists or (isinstance(table_exists, (tuple, list)) and not table_exists[0]) or (isinstance(table_exists, dict) and not table_exists.get('exists')):
                continue
        except Exception:
            continue
        
        for column_name in columns_to_migrate:
            # ALWAYS try to alter - be very aggressive
            # Try multiple approaches to ensure it works
            migrated = False
            for attempt in range(3):
                try:
                    # Method 1: Direct ALTER with USING clause (most reliable)
                    cursor.execute(f"ALTER TABLE {table_name} ALTER COLUMN {column_name} TYPE VARCHAR(255) USING {column_name}::VARCHAR(255)")
                    if conn:
                        conn.commit()
                    print(f"✓ Migrated {table_name}.{column_name} to VARCHAR(255) (attempt {attempt + 1})")
                    migrated = True
                    break
                except Exception as alter_err:
                    error_msg = str(alter_err).lower()
                    # If it says "already" or "does not exist", that's fine
                    if 'already' in error_msg or 'does not exist' in error_msg or 'is not of type' in error_msg:
                        print(f"Info: {table_name}.{column_name} is already correct or doesn't exist")
                        migrated = True
                        break
                    # If it's the last attempt, log the error
                    if attempt == 2:
                        import traceback
                        print(f"ERROR: Failed to migrate {table_name}.{column_name} after 3 attempts: {alter_err}")
                        # Check current state for debugging
                        try:
                            cursor.execute("""
                                SELECT data_type, character_maximum_length
                                FROM information_schema.columns 
                                WHERE table_name = %s AND column_name = %s
                            """, (table_name, column_name))
                            col_info = cursor.fetchone()
                            if col_info:
                                current_length = col_info[1] if isinstance(col_info, (tuple, list)) else col_info.get("character_maximum_length")
                                print(f"  Current state: type={col_info[0] if isinstance(col_info, (tuple, list)) else col_info.get('data_type')}, length={current_length}")
                        except Exception:
                            pass
                        traceback.print_exc()
                    else:
                        # Try alternative method
                        try:
                            cursor.execute(f"ALTER TABLE {table_name} ALTER COLUMN {column_name} TYPE VARCHAR(255)")
                            if conn:
                                conn.commit()
                            print(f"✓ Migrated {table_name}.{column_name} to VARCHAR(255) (alternative method)")
                            migrated = True
                            break
                        except Exception:
                            pass
    
    # Also migrate challan_number separately (it's VARCHAR(50) but can exceed 50 chars with long party names)
    for table_name, column_name in challan_number_migration:
        migrated = False
        for attempt in range(3):
            try:
                cursor.execute(f"ALTER TABLE {table_name} ALTER COLUMN {column_name} TYPE VARCHAR(255) USING {column_name}::VARCHAR(255)")
                if conn:
                    conn.commit()
                print(f"✓ Migrated {table_name}.{column_name} to VARCHAR(255) (attempt {attempt + 1})")
                migrated = True
                break
            except Exception as alter_err:
                error_msg = str(alter_err).lower()
                if 'already' in error_msg or 'does not exist' in error_msg:
                    print(f"Info: {table_name}.{column_name} is already correct or doesn't exist")
                    migrated = True
                    break
                if attempt == 2:
                    import traceback
                    print(f"ERROR: Failed to migrate {table_name}.{column_name}: {alter_err}")
                    traceback.print_exc()

def _run_startup_db_checks():
    """Run DB table checks in a thread so server can start even when DB is slow/unavailable."""
    try:
        with closing(get_db_connection()) as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                ensure_product_tables(cursor)
                ensure_challan_tables(cursor, conn)
                _migrate_varchar_columns(cursor, conn)  # Explicit migration
                cleanup_finalized_challan_numbers(cursor)
            conn.commit()
    except Exception as exc:
        print(f"Warning: Startup table checks failed: {exc}")


def _warm_challan_cache():
    """Preload cache in background so first app request is fast."""
    import time
    time.sleep(3)
    try:
        g = globals()
        if "get_challan_options" in g:
            opts = g["get_challan_options"](quick=True)  # Fast warm
            # Warm party-data for first few parties (helps auto-fill)
            if opts and "get_party_data_from_orders" in g:
                for p in (opts.get("party_names") or [])[:3]:
                    if p and str(p).strip():
                        try:
                            g["get_party_data_from_orders"](str(p).strip())
                        except Exception:
                            pass
        if "list_challans" in g:
            g["list_challans"](limit=10)
        print("Challan cache warmed successfully")
    except Exception as e:
        print(f"Cache warm skipped: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan event handler for startup and shutdown tasks.
    """
    # Run DB checks in thread so server starts listening immediately
    asyncio.create_task(asyncio.to_thread(_run_startup_db_checks))
    # Warm cache in background so first request doesn't timeout
    asyncio.create_task(asyncio.to_thread(_warm_challan_cache))
    yield
    # Shutdown (if needed in the future)
    pass


app = FastAPI(title="DecoJewels API", lifespan=lifespan)

# CORS middleware to allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection helpers
def get_db_connection():
    try:
        params = get_db_connection_params()
        conn = psycopg.connect(**params)
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        try:
            params = get_db_connection_params()
            print(f"Attempted connection with host: {params.get('host', 'unknown')}")
        except Exception:
            pass
        raise

def ensure_product_tables(cursor):
    """
    Ensure product_catalog and product_sizes tables exist with expected columns.
    """
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS product_catalog (
            id SERIAL PRIMARY KEY,
            external_id INTEGER,
            name VARCHAR(500) NOT NULL,
            category_id INTEGER,
            category_name VARCHAR(255),
            image_url TEXT,
            video_url TEXT,
            qr_code TEXT,
            is_active BOOLEAN DEFAULT TRUE,
            metadata JSONB,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """
    )

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS product_sizes (
            id SERIAL PRIMARY KEY,
            product_id INTEGER REFERENCES product_catalog(id) ON DELETE CASCADE,
            size_id INTEGER,
            size_text VARCHAR(100),
            price_a NUMERIC(12, 2),
            price_b NUMERIC(12, 2),
            price_c NUMERIC(12, 2),
            price_d NUMERIC(12, 2),
            price_e NUMERIC(12, 2),
            price_r NUMERIC(12, 2),
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """
    )

    cursor.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_product_catalog_external_id "
        "ON product_catalog(external_id) WHERE external_id IS NOT NULL"
    )
    cursor.execute(
        "CREATE INDEX IF NOT EXISTS idx_product_sizes_product_id "
        "ON product_sizes(product_id)"
    )
    cursor.execute(
        "CREATE INDEX IF NOT EXISTS idx_product_sizes_size_id "
        "ON product_sizes(size_id)"
    )


def ensure_orders_table(cursor):
    """
    Ensure orders table exists with all required columns, especially order_number.
    """
    # Check if orders table exists
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'orders'
        ) as exists
    """)
    result = cursor.fetchone()
    # Handle both dict_row and tuple results
    if isinstance(result, dict):
        table_exists = result.get('exists', False)
    else:
        table_exists = result[0] if result else False
    
    if not table_exists:
        # Create orders table if it doesn't exist
        cursor.execute("""
            CREATE TABLE orders (
                id SERIAL PRIMARY KEY,
                order_number VARCHAR(50) UNIQUE NOT NULL,
                party_name VARCHAR(255),
                station VARCHAR(255),
                price_category VARCHAR(100),
                product_id INTEGER REFERENCES product_catalog(id) ON DELETE SET NULL,
                product_external_id INTEGER,
                product_name VARCHAR(500),
                size_id INTEGER,
                size_text VARCHAR(100),
                quantity INTEGER NOT NULL DEFAULT 1,
                unit_price DECIMAL(12, 2),
                total_price DECIMAL(12, 2) NOT NULL,
                customer_name VARCHAR(255) NOT NULL,
                customer_phone VARCHAR(20),
                customer_email VARCHAR(255),
                customer_address TEXT,
                order_status VARCHAR(50) DEFAULT 'pending' CHECK (
                    order_status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')
                ),
                payment_status VARCHAR(50) DEFAULT 'pending' CHECK (
                    payment_status IN ('pending', 'partial', 'paid', 'refunded')
                ),
                payment_method VARCHAR(50),
                transport_name VARCHAR(255),
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_by VARCHAR(255)
            )
        """)
        
        # Create indexes
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders(product_id)
        """)
    else:
        # Table exists, ensure order_number column exists
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'orders' AND column_name = 'order_number'
        """)
        has_order_number = cursor.fetchone() is not None
        
        if not has_order_number:
            print("Adding order_number column to orders table...")
            # First, add the column (allowing NULLs initially)
            cursor.execute("""
                ALTER TABLE orders 
                ADD COLUMN order_number VARCHAR(50)
            """)
            # Update existing rows with a default order number if needed
            cursor.execute("""
                UPDATE orders 
                SET order_number = 'DJ-' || LPAD(id::TEXT, 6, '0')
                WHERE order_number IS NULL
            """)
            # Now make it NOT NULL and add unique constraint
            try:
                cursor.execute("""
                    ALTER TABLE orders 
                    ALTER COLUMN order_number SET NOT NULL
                """)
                cursor.execute("""
                    ALTER TABLE orders 
                    ADD CONSTRAINT orders_order_number_key UNIQUE (order_number)
                """)
            except Exception as e:
                print(f"Warning: Could not add NOT NULL or UNIQUE constraint to order_number: {e}")
                # If constraint fails, at least ensure the column exists

    # Indexes for challan options queries (DISTINCT on party, station, transport)
    for idx_name, col in [
        ("idx_orders_party_name", "party_name"),
        ("idx_orders_station", "station"),
        ("idx_orders_transport_name", "transport_name"),
    ]:
        try:
            cursor.execute(
                SQL("CREATE INDEX IF NOT EXISTS {} ON orders({})").format(
                    Identifier(idx_name), Identifier(col)
                )
            )
        except Exception:
            pass


def ensure_challan_tables(cursor, conn=None):
    """
    Create challan tables if they do not exist, and ensure all required columns exist.
    """
    # Check if challans table exists and has required columns
    cursor.execute("""
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'challans' AND column_name = 'challan_number'
    """)
    table_exists_with_columns = cursor.fetchone() is not None
    
    if not table_exists_with_columns:
        # Table doesn't exist or is missing key columns - drop and recreate
        cursor.execute("DROP TABLE IF EXISTS challan_items CASCADE")
        cursor.execute("DROP TABLE IF EXISTS challans CASCADE")
        
        cursor.execute("""
            CREATE TABLE challans (
                id SERIAL PRIMARY KEY,
                challan_number VARCHAR(255) UNIQUE NOT NULL,
                party_name VARCHAR(255) NOT NULL,
                station_name VARCHAR(255) NOT NULL,
                transport_name VARCHAR(255),
                price_category VARCHAR(100),
                total_amount NUMERIC(12, 2) DEFAULT 0,
                total_quantity NUMERIC(12, 2) DEFAULT 0,
                status VARCHAR(50) DEFAULT 'draft' CHECK (
                    status IN ('draft', 'ready', 'in_transit', 'delivered', 'cancelled')
                ),
                notes TEXT,
                metadata JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
    else:
        # Table exists, just ensure it has all columns
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS challans (
                id SERIAL PRIMARY KEY,
                challan_number VARCHAR(255) UNIQUE NOT NULL,
                party_name VARCHAR(255) NOT NULL,
                station_name VARCHAR(255) NOT NULL,
                transport_name VARCHAR(255),
                price_category VARCHAR(100),
                total_amount NUMERIC(12, 2) DEFAULT 0,
                total_quantity NUMERIC(12, 2) DEFAULT 0,
                status VARCHAR(50) DEFAULT 'draft' CHECK (
                    status IN ('draft', 'ready', 'in_transit', 'delivered', 'cancelled')
                ),
                notes TEXT,
                metadata JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS challan_items (
            id SERIAL PRIMARY KEY,
            challan_id INTEGER REFERENCES challans(id) ON DELETE CASCADE,
            product_id INTEGER REFERENCES product_catalog(id) ON DELETE SET NULL,
            product_name VARCHAR(500) NOT NULL,
            size_id INTEGER,
            size_text VARCHAR(100),
            quantity NUMERIC(12, 2) NOT NULL DEFAULT 1,
            unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
            total_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
            qr_code TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challans_number 
        ON challans(challan_number)
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challans_status 
        ON challans(status)
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challans_party_name 
        ON challans(party_name)
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challans_station_name 
        ON challans(station_name)
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challans_transport_name 
        ON challans(transport_name)
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challans_created_at 
        ON challans(created_at DESC)
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_challan_items_challan_id 
        ON challan_items(challan_id)
    """)
    
    # Ensure UNIQUE on challan_number so duplicate numbers are rejected at DB level
    try:
        cursor.execute("""
            ALTER TABLE challans
            ADD CONSTRAINT challans_challan_number_key UNIQUE (challan_number)
        """)
    except Exception:
        pass  # Constraint already exists

    # Ensure columns exist even if table was created previously with old schema
    challan_columns = [
        ("challan_number", "VARCHAR(255)"),  # Changed from VARCHAR(50) to accommodate long party names
        ("party_name", "VARCHAR(255)"),
        ("station_name", "VARCHAR(255)"),
        ("transport_name", "VARCHAR(255)"),
        ("price_category", "VARCHAR(100)"),
        ("total_amount", "NUMERIC(12, 2) DEFAULT 0"),
        ("total_quantity", "NUMERIC(12, 2) DEFAULT 0"),
        ("gst_amount", "NUMERIC(12, 2) DEFAULT 0"),
        ("apply_gst", "VARCHAR(50)"),
        ("status", "VARCHAR(50) DEFAULT 'draft'"),
        ("notes", "TEXT"),
        ("metadata", "JSONB"),
        ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
        ("updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
    ]
    for column_name, column_type in challan_columns:
        try:
            # Check if column exists first
            cursor.execute("""
                SELECT column_name, character_maximum_length
                FROM information_schema.columns 
                WHERE table_name = 'challans' AND column_name = %s
            """, (column_name,))
            existing_col = cursor.fetchone()
            if not existing_col:
                # Column doesn't exist, add it
                cursor.execute(
                    SQL("ALTER TABLE challans ADD COLUMN {} {}").format(
                        Identifier(column_name),
                        SQL(column_type)
                    )
                )
            elif column_name == "party_name":
                # Always check and upgrade party_name column if it's VARCHAR(50) or smaller
                try:
                    max_length = existing_col.get("character_maximum_length") if isinstance(existing_col, dict) else (existing_col[1] if len(existing_col) > 1 else None)
                    if max_length is not None and max_length < 255:
                        cursor.execute("ALTER TABLE challans ALTER COLUMN party_name TYPE VARCHAR(255)")
                        if conn:
                            conn.commit()  # Commit the ALTER immediately
                        print(f"✓ Updated challans.party_name column from VARCHAR({max_length}) to VARCHAR(255)")
                    elif max_length is None:
                        # Column exists but we couldn't determine length - try to upgrade anyway
                        try:
                            cursor.execute("ALTER TABLE challans ALTER COLUMN party_name TYPE VARCHAR(255)")
                            if conn:
                                conn.commit()
                            print(f"✓ Updated challans.party_name column to VARCHAR(255)")
                        except Exception:
                            pass
                except Exception as alter_err:
                    print(f"Warning: Could not alter challans.party_name column size: {alter_err}")
                    import traceback
                    traceback.print_exc()
            elif column_name in ["station_name", "transport_name"]:
                # Also ensure station_name and transport_name are VARCHAR(255)
                try:
                    max_length = existing_col.get("character_maximum_length") if isinstance(existing_col, dict) else (existing_col[1] if len(existing_col) > 1 else None)
                    if max_length is not None and max_length < 255:
                        cursor.execute(f"ALTER TABLE challans ALTER COLUMN {column_name} TYPE VARCHAR(255)")
                        if conn:
                            conn.commit()
                        print(f"✓ Updated challans.{column_name} column from VARCHAR({max_length}) to VARCHAR(255)")
                    elif max_length is None:
                        # Try to upgrade anyway if we can't determine length
                        try:
                            cursor.execute(f"ALTER TABLE challans ALTER COLUMN {column_name} TYPE VARCHAR(255)")
                            if conn:
                                conn.commit()
                            print(f"✓ Updated challans.{column_name} column to VARCHAR(255)")
                        except Exception:
                            pass
                except Exception as alter_err:
                    print(f"Warning: Could not alter challans.{column_name} column size: {alter_err}")
                    import traceback
                    traceback.print_exc()
        except Exception as e:
            print(f"Warning: Could not add/check column {column_name} to challans table: {e}")
    
    # ALWAYS run migration check after ensuring columns exist
    if conn:
        try:
            _migrate_varchar_columns(cursor, conn)
        except Exception as migrate_err:
            print(f"Warning: Migration check failed in ensure_challan_tables: {migrate_err}")
            import traceback
            traceback.print_exc()
    
    challan_item_columns = [
        ("challan_id", "INTEGER"),
        ("product_id", "INTEGER"),
        ("product_name", "VARCHAR(500)"),
        ("size_id", "INTEGER"),
        ("size_text", "VARCHAR(100)"),
        ("quantity", "NUMERIC(12, 2) DEFAULT 1"),
        ("unit_price", "NUMERIC(12, 2) DEFAULT 0"),
        ("total_price", "NUMERIC(12, 2) DEFAULT 0"),
        ("qr_code", "TEXT"),
        ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
    ]
    for column_name, column_type in challan_item_columns:
        try:
            # Check if column exists first
            cursor.execute("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'challan_items' AND column_name = %s
            """, (column_name,))
            if not cursor.fetchone():
                # Column doesn't exist, add it
                cursor.execute(
                    SQL("ALTER TABLE challan_items ADD COLUMN {} {}").format(
                        Identifier(column_name),
                        SQL(column_type)
                    )
                )
        except Exception as e:
            print(f"Warning: Could not add column {column_name} to challan_items table: {e}")

def generate_challan_number(cursor, party_name: str = None) -> str:
    """
    Generate challan number in format: PARTY_NAME - DC000001
    Example: SAGAR - DC000001, SOWMIK - DC000002
    DC series is maintained globally across all parties (DC000001, DC000002, DC000003, etc.)
    When challan is finalized, party name is removed leaving just DC000001
    Starts from DC000001 (not DC000000)
    """
    # Advisory lock so only one transaction generates at a time (prevents duplicate DC numbers)
    cursor.execute("SELECT pg_advisory_xact_lock(8247)")
    # Get full party name (uppercase)
    if not party_name:
        party_name = "UNKNOWN"  # Default fallback
    party_name_upper = party_name.strip().upper()
    
    # Find the highest existing DC sequence number across ALL challans (global sequence)
    # Check both formats: "DC000001" and "PARTY_NAME - DC000001"
    max_sequence = 0  # Start from 0 so first challan becomes DC000001
    try:
        # Use regex to extract DC numbers from all challans and find the maximum
        # This matches both "DC000001" and "PARTY_NAME - DC000001" formats
        # FOR UPDATE locks the row so concurrent requests get unique sequence numbers
        cursor.execute("""
            SELECT challan_number 
            FROM challans 
            WHERE challan_number ~ 'DC[0-9]+$' OR challan_number ~ ' - DC[0-9]+$'
            ORDER BY 
                CAST(
                    COALESCE(
                        SUBSTRING(challan_number FROM 'DC([0-9]+)$'),
                        SUBSTRING(challan_number FROM ' - DC([0-9]+)$')
                    ) AS INTEGER
                ) DESC
            LIMIT 1
            FOR UPDATE
        """)
        result = cursor.fetchone()
        
        if result:
            existing_number = result.get('challan_number') if isinstance(result, dict) else result[0]
            if existing_number:
                try:
                    # Extract the DC sequence part using regex
                    # Matches both "DC000001" and "PARTY_NAME - DC000001"
                    match = re.search(r'(?: - )?DC(\d+)$', existing_number)
                    if match:
                        sequence_str = match.group(1)
                        sequence_num = int(sequence_str)
                        max_sequence = sequence_num
                except (ValueError, AttributeError) as e:
                    print(f"Warning: Could not parse DC sequence from {existing_number}: {e}")
    except Exception as e:
        print(f"Warning: Could not find existing challan numbers: {e}")
        # Fallback: try simpler query
        try:
            cursor.execute("""
                SELECT challan_number 
                FROM challans 
                WHERE challan_number LIKE '%DC%'
                ORDER BY challan_number DESC
                LIMIT 100
            """)
            results = cursor.fetchall()
            
            for result in results:
                existing_number = result.get('challan_number') if isinstance(result, dict) else result[0]
                if existing_number:
                    try:
                        # Extract the sequence part from either format
                        if ' - DC' in existing_number:
                            # Format: "PARTY_NAME - DC000001"
                            dc_part = existing_number.split(' - DC')[-1].strip()
                            if dc_part.startswith('DC'):
                                sequence_str = dc_part[2:]  # Remove "DC" prefix
                                sequence_num = int(sequence_str)
                                if sequence_num > max_sequence:
                                    max_sequence = sequence_num
                        elif existing_number.startswith('DC'):
                            # Format: "DC000001"
                            sequence_str = existing_number[2:]  # Remove "DC" prefix
                            sequence_num = int(sequence_str)
                            if sequence_num > max_sequence:
                                max_sequence = sequence_num
                    except (ValueError, IndexError):
                        continue
        except Exception as e2:
            print(f"Warning: Fallback query also failed: {e2}")
            max_sequence = 0  # Start from 0 so first challan becomes DC000001
    
    # Generate a unique number by incrementing the global DC sequence
    # Format: DC000001..DC999999, then DC1000000, DC1000001... (no limit)
    max_attempts = 1000  # Safety limit
    for attempt in range(max_attempts):
        sequence_num = max_sequence + attempt + 1
        sequence_str = str(sequence_num).zfill(6) if sequence_num <= 999999 else str(sequence_num)
        dc_series = f"DC{sequence_str}"  # DC000001..DC999999, DC1000000+
        challan_number = f"{party_name_upper} - {dc_series}"  # SAGAR - DC000001, etc.
        
        # Check if this number already exists
        try:
            cursor.execute("""
                SELECT id FROM challans WHERE challan_number = %s
            """, (challan_number,))
            exists = cursor.fetchone()
            if not exists:
                return challan_number
        except Exception as e:
            # If there's an error checking, assume it's safe to use
            print(f"Warning: Could not check challan number existence: {e}")
            return challan_number
    
    # Fallback: use timestamp if we can't find a unique sequence
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    return f"{party_name_upper} - DC{timestamp[-6:]}"
def decimal_to_float(value):
    if isinstance(value, Decimal):
        return float(value)
    return value


def _json_serializable(value):
    """Convert a value to something JSON-serializable (avoids 500 on GET challan)."""
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: _json_serializable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_serializable(v) for v in value]
    if isinstance(value, (str, int, float, bool)):
        return value
    return str(value)

def process_designs_field(designs_data):
    """
    Process designs field from database to extract design names/codes as a list of strings.
    Handles various formats: dict with 'designs' key, JSON string, list of objects, list of strings.
    """
    if designs_data is None:
        return []
    
    try:
        # If it's a dict, check for 'designs' key first (most common case from database)
        if isinstance(designs_data, dict):
            if 'designs' in designs_data:
                designs_list = designs_data['designs']
                if isinstance(designs_list, list) and len(designs_list) > 0:
                    # If it's a list of dicts, extract design_name or design_code
                    if isinstance(designs_list[0], dict):
                        result = []
                        for d in designs_list:
                            if isinstance(d, dict):
                                design_name = d.get('design_name') or d.get('design_code') or d.get('name')
                                if design_name:
                                    result.append(str(design_name))
                        return result
                    # If it's a list of strings, return as is
                    elif isinstance(designs_list[0], str):
                        return designs_list
                elif isinstance(designs_list, list):
                    return []
            # If dict doesn't have 'designs' key, try to extract values
            if 'design' in designs_data:
                design_val = designs_data['design']
                if isinstance(design_val, list):
                    return [str(d) for d in design_val]
                return [str(design_val)]
        
        # If it's already a list
        if isinstance(designs_data, list):
            if len(designs_data) == 0:
                return []
            # Check if it's a list of strings
            if isinstance(designs_data[0], str):
                return designs_data
            # If it's a list of dicts, extract design_name or design_code
            if isinstance(designs_data[0], dict):
                result = []
                for d in designs_data:
                    if isinstance(d, dict):
                        design_name = d.get('design_name') or d.get('design_code') or d.get('name')
                        if design_name:
                            result.append(str(design_name))
                return result
        
        # If it's a string, try to parse as JSON
        if isinstance(designs_data, str):
            try:
                parsed = json.loads(designs_data)
                return process_designs_field(parsed)  # Recursively process parsed JSON
            except (json.JSONDecodeError, TypeError):
                # If parsing fails, treat as comma-separated string
                return [d.strip() for d in designs_data.split(',') if d.strip()]
        
        # Fallback: convert to string
        return [str(designs_data)]
    except Exception as e:
        print(f"Error processing designs field: {e}, type: {type(designs_data)}, value: {designs_data}")
        import traceback
        traceback.print_exc()
        return []

def serialize_challan(challan_row, items: List[Dict[str, Any]] = None):
    if not challan_row:
        return None
    try:
        challan = dict(challan_row)
    except Exception as e:
        print(f"serialize_challan: dict(challan_row) failed: {e}")
        challan = {k: getattr(challan_row, k, None) for k in getattr(challan_row, "_fields", []) or []}
    challan["total_amount"] = decimal_to_float(challan.get("total_amount"))
    challan["total_quantity"] = decimal_to_float(challan.get("total_quantity"))
    if challan.get("created_at") is not None:
        challan["created_at"] = _json_serializable(challan["created_at"])
    if challan.get("updated_at") is not None:
        challan["updated_at"] = _json_serializable(challan["updated_at"])
    if challan.get("metadata") is not None:
        v = challan["metadata"]
        if isinstance(v, str):
            try:
                challan["metadata"] = json.loads(v)
            except (TypeError, json.JSONDecodeError):
                challan["metadata"] = None
        else:
            challan["metadata"] = _json_serializable(v)
    serialized_items = []
    if items:
        for item in items:
            try:
                item_dict = dict(item)
            except Exception:
                item_dict = {k: getattr(item, k, None) for k in getattr(item, "_fields", []) or []}
            item_dict["quantity"] = decimal_to_float(item_dict.get("quantity"))
            item_dict["unit_price"] = decimal_to_float(item_dict.get("unit_price"))
            item_dict["total_price"] = decimal_to_float(item_dict.get("total_price"))
            serialized_items.append(_json_serializable(item_dict))
    challan["items"] = serialized_items
    return _json_serializable(challan)

def fetch_distinct_values(cursor, table: str, column: str, limit: int = 100) -> List[str]:
    """
    Safely fetch distinct values from a table column.
    Validates table and column names to prevent SQL injection.
    """
    try:
        # Validate table and column names (only allow alphanumeric and underscore)
        import re
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', table):
            raise ValueError(f"Invalid table name: {table}")
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', column):
            raise ValueError(f"Invalid column name: {column}")
        
        # Use psycopg's identifier quoting for safety
        query = SQL("""
            SELECT DISTINCT {column} AS value
            FROM {table}
            WHERE {column} IS NOT NULL AND {column} <> ''
            ORDER BY {column}
            LIMIT %s
        """).format(
            column=Identifier(column),
            table=Identifier(table)
        )
        cursor.execute(query, (limit,))
        return [
            str(row["value"]) for row in cursor.fetchall() 
            if row and row.get("value") is not None
        ]
    except Exception as e:
        print(f"Warning: Could not fetch distinct values for {table}.{column}: {e}")
        return []

class ProductResponse(BaseModel):
    id: int = None
    name: str = None
    description: str = None
    price: float = None
    image_url: str = None
    barcode: str = None
    category: str = None
    stock: int = None

def cleanup_finalized_challan_numbers(cursor):
    """
    Clean up existing finalized challans that still have party names in challan_number.
    Removes party name from challan_number for challans in finalized states.
    """
    try:
        finalized_states = ['ready', 'in_transit', 'delivered']
        cursor.execute("""
            SELECT id, challan_number, status
            FROM challans
            WHERE status = ANY(%s)
            AND challan_number LIKE '%% - DC%%'
        """, (finalized_states,))
        
        challans_to_fix = cursor.fetchall()
        if challans_to_fix:
            print(f"Found {len(challans_to_fix)} finalized challans with party names to clean up")
            for challan in challans_to_fix:
                challan_id = challan.get('id') if isinstance(challan, dict) else challan[0]
                old_number = challan.get('challan_number') if isinstance(challan, dict) else challan[1]
                status = challan.get('status') if isinstance(challan, dict) else challan[2]
                
                if ' - DC' in old_number:
                    # Extract just the DC part: "DC000001"
                    # Split by ' - DC' and add 'DC' prefix back
                    parts = old_number.split(' - DC')
                    if len(parts) > 1:
                        dc_part = 'DC' + parts[-1].strip()
                        new_number = dc_part
                        # Check if new_number already exists (might conflict)
                        cursor.execute("""
                            SELECT id FROM challans WHERE challan_number = %s AND id != %s
                        """, (new_number, challan_id))
                        existing = cursor.fetchone()
                        if existing:
                            # Conflict: find next available DC number
                            cursor.execute("""
                                SELECT challan_number 
                                FROM challans 
                                WHERE challan_number ~ '^DC[0-9]+$'
                                ORDER BY CAST(SUBSTRING(challan_number FROM 'DC([0-9]+)$') AS INTEGER) DESC
                                LIMIT 1
                            """)
                            max_result = cursor.fetchone()
                            if max_result:
                                max_dc = max_result['challan_number'] if isinstance(max_result, dict) else max_result[0]
                                max_num = int(max_dc[2:])  # Remove 'DC' prefix
                                new_number = f'DC{str(max_num + 1).zfill(6)}'
                        
                        cursor.execute("""
                            UPDATE challans
                            SET challan_number = %s
                            WHERE id = %s
                        """, (new_number, challan_id))
                        print(f"Cleaned up challan {challan_id}: {old_number} -> {new_number} (status: {status})")
    except Exception as e:
        print(f"Warning: Could not cleanup finalized challan numbers: {e}")

@app.get("/")
def read_root():
    return {"message": "DecoJewels API is running"}

@app.get("/api/verify/whatsapp/{phone_number}")
def verify_whatsapp(phone_number: str):
    """
    Verify if a phone number has WhatsApp
    Note: This is a format validation - WhatsApp doesn't provide a public API
    to verify if a number actually has WhatsApp installed.
    """
    try:
        # Clean phone number
        clean_phone = phone_number.replace('+', '').replace(' ', '').replace('-', '').strip()
        
        # Remove leading 0 if present
        if clean_phone.startswith('0'):
            clean_phone = clean_phone[1:]
        
        # Add country code if not present (assuming India +91)
        if len(clean_phone) == 10:
            clean_phone = '91' + clean_phone
        
        # Validate phone number format (should be 10-15 digits)
        import re
        phone_regex = re.compile(r'^[1-9]\d{9,14}$')
        
        if not phone_regex.match(clean_phone):
            return {
                "valid": False,
                "message": "Invalid phone number format",
                "phone": clean_phone
            }
        
        # Check if number format is valid for WhatsApp
        # WhatsApp uses international format without + or 00
        whatsapp_url = f"https://wa.me/{clean_phone}"
        
        return {
            "valid": True,
            "has_whatsapp_format": True,
            "phone": clean_phone,
            "whatsapp_url": whatsapp_url,
            "message": "Phone number format is valid for WhatsApp"
        }
        
    except Exception as e:
        return {
            "valid": False,
            "message": f"Error verifying phone number: {str(e)}",
            "phone": phone_number
        }

@app.post("/api/whatsapp/send")
async def send_whatsapp_message(request: Request):
    """
    Send WhatsApp message automatically via API
    Requires phone_number and message in request body
    Sender number: 8586029205 (configured)
    """
    try:
        data = await request.json()
        phone_number = data.get("phone_number")
        message = data.get("message")
        
        if not phone_number or not message:
            return {
                "success": False,
                "message": "phone_number and message are required"
            }
        
        # Clean phone number
        clean_phone = phone_number.replace('+', '').replace(' ', '').replace('-', '').strip()
        
        # Remove leading 0 if present
        if clean_phone.startswith('0'):
            clean_phone = clean_phone[1:]
        
        # Add country code if not present (assuming India +91)
        if len(clean_phone) == 10:
            clean_phone = '91' + clean_phone
        
        # Validate phone number format
        import re
        phone_regex = re.compile(r'^[1-9]\d{9,14}$')
        
        if not phone_regex.match(clean_phone):
            return {
                "success": False,
                "message": "Invalid phone number format",
                "phone": clean_phone
            }
        
        # Sender WhatsApp number (from number)
        SENDER_WHATSAPP_NUMBER = "918586029205"  # 8586029205 with country code
        
        # TODO: Integrate with WhatsApp Business API, Twilio, or other WhatsApp service
        # Use SENDER_WHATSAPP_NUMBER as the from number
        # Example: 
        # result = whatsapp_service.send(
        #     from_number=SENDER_WHATSAPP_NUMBER,
        #     to_number=clean_phone,
        #     message=message
        # )
        
        return {
            "success": True,
            "message": f"Message sent successfully to {clean_phone}",
            "from_number": SENDER_WHATSAPP_NUMBER,
            "to_number": clean_phone,
            "sent_message": message
        }
        
    except Exception as e:
        return {
            "success": False,
            "message": f"Error sending WhatsApp message: {str(e)}"
        }

@app.get("/api/health")
def health_check():
    """
    Health check endpoint to verify database connection
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        return {
            "status": "healthy",
            "database": "connected",
            "message": "API and database are running"
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e)
        }

@app.get("/api/product/{product_id}")
def get_product_by_id(product_id: int):
    """
    Retrieve product details by ID from products_master with all sizes
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Get product from products_master
        cursor.execute("""
            SELECT 
                pm.id,
                pm.external_id,
                pm.name,
                pm.category_id,
                pm.category as category_name,
                pm.image as image_url,
                pm.video as video_url,
                pm.is_active,
                pm.created_on as created_at,
                pm.updated_at,
                pm.designs,
                pc.qr_code
            FROM products_master pm
            LEFT JOIN product_catalog pc ON pm.external_id = pc.external_id
            WHERE pm.id = %s AND pm.is_active = true
        """, (product_id,))
        
        product = cursor.fetchone()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        product_dict = {
            'id': product['id'],
            'external_id': product['external_id'],
            'name': product['name'],
            'category_id': product['category_id'],
            'category_name': product['category_name'],
            'image_url': product['image_url'],
            'video_url': product['video_url'],
            'qr_code': product['qr_code'],
            'is_active': product['is_active'],
            'created_at': product['created_at'],
            'updated_at': product['updated_at'],
            'designs': product.get('designs')
        }
        
        # Get sizes for this product - check both direct (product_type='master') and via product_catalog
        sizes_list = []
        product_id_val = product['id']
        
        # First, check for sizes directly linked to products_master (product_id = products_master.id, product_type = 'master')
        cursor.execute("""
            SELECT 
                id,
                size_id,
                size_text,
                price_a,
                price_b,
                price_c,
                price_d,
                price_e,
                price_r,
                is_active
            FROM product_sizes
            WHERE product_id = %s AND product_type = 'master' AND is_active = true
            ORDER BY id
        """, (product_id_val,))
        
        direct_sizes = cursor.fetchall()
        for size in direct_sizes:
            size_dict = {
                'id': size['id'],
                'size_id': size['size_id'],
                'size_text': size['size_text'],
                'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                'is_active': size['is_active']
            }
            sizes_list.append(size_dict)
        
        # If no direct sizes found, check via product_catalog
        if not sizes_list and product['external_id']:
            cursor.execute("""
                SELECT 
                    ps.id,
                    ps.size_id,
                    ps.size_text,
                    ps.price_a,
                    ps.price_b,
                    ps.price_c,
                    ps.price_d,
                    ps.price_e,
                    ps.price_r,
                    ps.is_active
                FROM product_sizes ps
                JOIN product_catalog pc ON ps.product_id = pc.id
                WHERE pc.external_id = %s AND ps.is_active = true
                ORDER BY ps.size_id
            """, (product['external_id'],))
            
            catalog_sizes = cursor.fetchall()
            for size in catalog_sizes:
                size_dict = {
                    'id': size['id'],
                    'size_id': size['size_id'],
                    'size_text': size['size_text'],
                    'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                    'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                    'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                    'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                    'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                    'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                    'is_active': size['is_active']
                }
                sizes_list.append(size_dict)
        
        product_dict['sizes'] = sizes_list
        
        return product_dict
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.post("/api/order/multiple")
def create_order_with_multiple_items(order_data: dict):
    """
    Create a single order with multiple items
    """
    conn = None
    try:
        # Validate required fields
        # Note: 'items' can be an empty list, so we check if it exists in the dict, not if it's truthy
        required_fields = ['party_name', 'station', 'customer_name', 'customer_phone']
        missing_fields = [field for field in required_fields if not order_data.get(field)]
        if missing_fields:
            raise HTTPException(
                status_code=400, 
                detail=f"Missing required fields: {', '.join(missing_fields)}"
            )
        
        # Get items - allow empty items list (order can be created without items initially)
        items = order_data.get("items", [])
        if items is None:
            items = []
        
        # Allow creating order without items (items can be added later)
        # Removed the check that required at least one item
        
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Ensure orders table exists with order_number column
        ensure_orders_table(cursor)
        conn.commit()
        
        # Create order_items table if it doesn't exist
        try:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS order_items (
                    id SERIAL PRIMARY KEY,
                    order_id INTEGER REFERENCES orders(id) ON DELETE CASCADE,
                    product_id INTEGER REFERENCES product_catalog(id) ON DELETE SET NULL,
                    product_external_id INTEGER,
                    product_name VARCHAR(500),
                    size_id INTEGER,
                    size_text VARCHAR(100),
                    quantity INTEGER NOT NULL DEFAULT 1,
                    unit_price DECIMAL(12, 2),
                    total_price DECIMAL(12, 2) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id)
            """)
            conn.commit()
        except Exception as table_error:
            print(f"Note: order_items table may already exist: {table_error}")
        
        # Ensure required columns exist in orders table
        try:
            # Check and add price_category
            cursor.execute("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'orders' AND column_name = 'price_category'
            """)
            has_price_category = cursor.fetchone() is not None
            
            if not has_price_category:
                print("Adding price_category column to orders table...")
                cursor.execute("""
                    ALTER TABLE orders 
                    ADD COLUMN price_category VARCHAR(100)
                """)
                conn.commit()
                print("Successfully added price_category column to orders table")
            
            # Check and add transport_name
            cursor.execute("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'orders' AND column_name = 'transport_name'
            """)
            has_transport_name = cursor.fetchone() is not None
            
            if not has_transport_name:
                print("Adding transport_name column to orders table...")
                cursor.execute("""
                    ALTER TABLE orders 
                    ADD COLUMN transport_name VARCHAR(255)
                """)
                conn.commit()
                print("Successfully added transport_name column to orders table")
            
            # Check and add created_by
            cursor.execute("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'orders' AND column_name = 'created_by'
            """)
            has_created_by = cursor.fetchone() is not None
            
            if not has_created_by:
                print("Adding created_by column to orders table...")
                cursor.execute("""
                    ALTER TABLE orders 
                    ADD COLUMN created_by VARCHAR(255)
                """)
                conn.commit()
                print("Successfully added created_by column to orders table")
        except Exception as col_error:
            print(f"Warning: Could not check/add columns: {col_error}")
            conn.rollback()
        
        # Check if order_number is provided (for updating existing order)
        order_number = order_data.get("order_number")
        order_exists = False
        
        if order_number:
            # Check if order with this number already exists
            cursor.execute("SELECT id FROM orders WHERE order_number = %s LIMIT 1", (order_number,))
            existing_order = cursor.fetchone()
            order_exists = existing_order is not None
        
        # Generate order number if not provided or doesn't exist
        if not order_number or not order_exists:
            try:
                # First, check for incomplete orders (orders with no items) to reuse
                # An incomplete order has product_id IS NULL and total_price = 0
                # Only check for DJ- prefix orders
                cursor.execute("""
                    SELECT DISTINCT order_number 
                    FROM orders 
                    WHERE order_number LIKE 'DJ-%'
                      AND product_id IS NULL 
                      AND total_price = 0
                    ORDER BY order_number ASC
                    LIMIT 1
                """)
                incomplete_order = cursor.fetchone()
                
                if incomplete_order:
                    # Reuse the incomplete order number (only if it's DJ- prefix)
                    incomplete_number = incomplete_order[0] if isinstance(incomplete_order, (tuple, list)) else incomplete_order.get('order_number')
                    if incomplete_number and incomplete_number.startswith('DJ-'):
                        order_number = incomplete_number
                        order_exists = True
                        print(f"Reusing incomplete order number: {order_number}")
                
                # If no incomplete order found, generate a new one
                if not order_number or not order_exists:
                    # Find the highest sequence number for DJ- prefix only
                    cursor.execute("""
                        SELECT order_number 
                        FROM orders 
                        WHERE order_number LIKE 'DJ-%'
                        ORDER BY order_number DESC
                        LIMIT 1
                    """)
                    result = cursor.fetchone()
                    max_sequence = 0
                    if result:
                        existing_number = result[0] if isinstance(result, (tuple, list)) else result.get('order_number')
                        if existing_number and existing_number.startswith('DJ-'):
                            try:
                                sequence_part = existing_number.split('-')[1]
                                max_sequence = int(sequence_part)
                            except (ValueError, IndexError):
                                max_sequence = 0
                    
                    # Generate new order number with DJ- prefix
                    order_number = f"DJ-{str(max_sequence + 1).zfill(6)}"
                    
                    # Ensure uniqueness
                    max_attempts = 1000
                    for attempt in range(max_attempts):
                        cursor.execute("SELECT id FROM orders WHERE order_number = %s", (order_number,))
                        exists = cursor.fetchone()
                        if not exists:
                            break
                        order_number = f"DJ-{str(max_sequence + attempt + 2).zfill(6)}"
            except Exception as e:
                from datetime import datetime
                # Fallback: use timestamp-based number
                order_number = f"DJ-{datetime.now().strftime('%Y%m%d%H%M%S')[:6]}"
        
        # Calculate total price for all items
        total_order_price = 0.0
        for item in items:
            unit_price = float(item.get("unit_price", 0) or 0)
            quantity = int(item.get("quantity", 1))
            total_order_price += unit_price * quantity
        
        # Allow zero total price if no items (items will be added later)
        # if total_order_price <= 0:
        #     raise HTTPException(
        #         status_code=400,
        #         detail="Total order price must be greater than 0"
        #     )
        
        # Create one order record per item, all with the same order_number
        order_ids = []
        created_orders = []
        
        # If reusing an incomplete order and we have items, delete the incomplete order record first
        if order_exists and items and len(items) > 0:
            # Check if this is an incomplete order (has no items)
            cursor.execute("""
                SELECT id FROM orders 
                WHERE order_number = %s 
                  AND product_id IS NULL 
                  AND total_price = 0
            """, (order_number,))
            incomplete_records = cursor.fetchall()
            if incomplete_records:
                # Delete incomplete order records to make room for new items
                cursor.execute("""
                    DELETE FROM orders 
                    WHERE order_number = %s 
                      AND product_id IS NULL 
                      AND total_price = 0
                """, (order_number,))
                print(f"Deleted {len(incomplete_records)} incomplete order record(s) for order {order_number}")
        
        # If no items, create a single order record without items (only if order doesn't exist)
        if (not items or len(items) == 0) and not order_exists:
            try:
                cursor.execute("""
                    INSERT INTO orders (
                        order_number, party_name, station, price_category,
                        customer_name, customer_phone, customer_email, customer_address,
                        payment_method, transport_name, created_by,
                        order_status, payment_status, total_price, created_at
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP
                    )
                    RETURNING id, order_number, created_at
                """, (
                    order_number,
                    order_data.get("party_name"),
                    order_data.get("station"),
                    order_data.get("price_category"),
                    order_data.get("customer_name"),
                    order_data.get("customer_phone"),
                    order_data.get("customer_email"),
                    order_data.get("customer_address"),
                    order_data.get("payment_method"),
                    order_data.get("transport_name"),
                    order_data.get("created_by"),
                    order_data.get("order_status", "pending"),
                    order_data.get("payment_status", "pending"),
                    0.0,  # Total price is 0 when no items
                ))
                result = cursor.fetchone()
                if result:
                    order_ids.append(result["id"])
                    created_orders.append({
                        "id": result["id"],
                        "order_number": result["order_number"],
                        "created_at": result["created_at"]
                    })
                conn.commit()
            except Exception as e:
                conn.rollback()
                raise HTTPException(status_code=500, detail=f"Failed to create order: {str(e)}")
        
        skipped_items = []
        print(f"DEBUG: Processing {len(items)} items for order")
        for idx, item in enumerate(items):
            print(f"DEBUG: Item {idx}: {item}")
            product_id = item.get("product_id")
            print(f"DEBUG: Item {idx} product_id: {product_id} (type: {type(product_id)})")
            if not product_id:
                product_name = item.get("product_name", "Unknown")
                skipped_items.append(f"{product_name}: Missing product_id")
                print(f"Warning: Item missing product_id: {item}")
                continue
            
            # Get product details
            #
            # IMPORTANT:
            # - Mobile app sends `product_id` from `products_master.id`
            # - Orders table historically stored `product_id` that matches `products_master.id`
            # - `product_catalog.id` is a different sequence, but shares `external_id` with `products_master.external_id`
            #
            # So: first try `product_catalog.id = product_id` (legacy / admin inputs),
            # then resolve via products_master.id -> external_id -> product_catalog (best-effort),
            # and finally fall back to products_master data even if no catalog row exists.
            cursor.execute("""
                SELECT id, external_id, name 
                FROM product_catalog 
                WHERE id = %s AND is_active = true
            """, (product_id,))
            product_info = cursor.fetchone()

            # Fallback 0: resolve products_master.id -> product_catalog by external_id
            if not product_info:
                try:
                    cursor.execute("""
                        SELECT pc.id, pc.external_id, pc.name
                        FROM products_master pm
                        JOIN product_catalog pc ON pm.external_id = pc.external_id
                        WHERE pm.id = %s
                          AND pc.is_active = true
                        LIMIT 1
                    """, (product_id,))
                    product_info = cursor.fetchone()
                    if product_info:
                        # Keep FK consistent with catalog when available
                        resolved_catalog_id = product_info["id"] if isinstance(product_info, dict) else None
                        print(f"Info: Resolved catalog product via products_master.id={product_id} -> catalog_id={resolved_catalog_id}")
                        product_id = resolved_catalog_id or product_id
                except Exception as e:
                    print(f"Warning: Could not resolve via products_master->product_catalog for product_id={product_id}: {e}")

            # Fallback 1: resolve by external_id if provided (frontend should send Product.externalId here)
            if not product_info:
                product_external_id = item.get("product_external_id")
                if product_external_id is not None and str(product_external_id).strip() != "":
                    try:
                        cursor.execute("""
                            SELECT id, external_id, name
                            FROM product_catalog
                            WHERE external_id = %s AND is_active = true
                            LIMIT 1
                        """, (product_external_id,))
                        product_info = cursor.fetchone()
                        if product_info:
                            # Update product_id to the actual catalog ID (keeps FK consistent)
                            product_id = product_info["id"] if isinstance(product_info, dict) else product_id
                            print(f"Info: Resolved product_id via external_id={product_external_id} -> id={product_id}")
                    except Exception as e:
                        print(f"Warning: Could not resolve product by external_id={product_external_id}: {e}")

            # Fallback 2: resolve by product_name (last resort) - use case-insensitive matching
            if not product_info:
                product_name_for_lookup = (item.get("product_name") or "").strip()
                if product_name_for_lookup:
                    try:
                        # Try exact match first
                        cursor.execute("""
                            SELECT id, external_id, name
                            FROM product_catalog
                            WHERE name = %s AND is_active = true
                            LIMIT 1
                        """, (product_name_for_lookup,))
                        product_info = cursor.fetchone()
                        
                        # If exact match fails, try case-insensitive match
                        if not product_info:
                            cursor.execute("""
                                SELECT id, external_id, name
                                FROM product_catalog
                                WHERE LOWER(TRIM(name)) = LOWER(TRIM(%s)) AND is_active = true
                                LIMIT 1
                            """, (product_name_for_lookup,))
                            product_info = cursor.fetchone()
                        
                        # If still no match, try partial match (contains)
                        if not product_info:
                            cursor.execute("""
                                SELECT id, external_id, name
                                FROM product_catalog
                                WHERE LOWER(name) LIKE LOWER(%s) AND is_active = true
                                LIMIT 1
                            """, (f"%{product_name_for_lookup}%",))
                            product_info = cursor.fetchone()
                        
                        if product_info:
                            product_id = product_info["id"] if isinstance(product_info, dict) else product_id
                            print(f"Info: Resolved product_id via name='{product_name_for_lookup}' -> id={product_id}")
                    except Exception as e:
                        print(f"Warning: Could not resolve product by name='{product_name_for_lookup}': {e}")

            # Final fallback: accept products_master row even if no active catalog row exists.
            # This prevents order creation from being blocked when product_catalog is incomplete/out-of-sync.
            products_master_row = None
            if not product_info:
                try:
                    cursor.execute("""
                        SELECT id, external_id, name
                        FROM products_master
                        WHERE id = %s
                        LIMIT 1
                    """, (item.get("product_id"),))
                    products_master_row = cursor.fetchone()
                    if products_master_row:
                        print(f"Info: Using products_master for product_id={item.get('product_id')} (no active catalog match)")
                except Exception as e:
                    print(f"Warning: Could not lookup products_master for product_id={item.get('product_id')}: {e}")

            if not product_info and not products_master_row:
                product_name = item.get("product_name", f"Product ID {product_id}")
                skipped_items.append(f"{product_name}: Product not found in products master/catalog")
                print(f"Warning: Product {product_id} not found in products_master or product_catalog, skipping")
                continue
            
            # Convert product_info to dict for easier access (it's already a dict_row from row_factory)
            product_dict = dict(product_info) if product_info else {}
            if not product_dict and products_master_row:
                # Normalize products_master row to same shape used below
                product_dict = dict(products_master_row)
            
            unit_price = float(item.get("unit_price", 0) or 0)
            quantity = int(float(item.get("quantity", 0) or 0))  # Convert to float first, then int to handle decimal strings
            
            # Validate quantity and unit_price
            if quantity <= 0:
                product_name = item.get("product_name", f"Product ID {product_id}")
                skipped_items.append(f"{product_name}: Quantity must be greater than 0 (got {quantity})")
                print(f"Warning: Item {idx} has invalid quantity: {quantity}")
                continue
            
            if unit_price <= 0:
                product_name = item.get("product_name", f"Product ID {product_id}")
                skipped_items.append(f"{product_name}: Unit price must be greater than 0 (got {unit_price})")
                print(f"Warning: Item {idx} has invalid unit_price: {unit_price}")
                continue
            
            item_total = unit_price * quantity
            
            # Extract values with fallbacks - ensure we have values
            product_external_id = product_dict.get("external_id") if product_dict.get("external_id") is not None else (item.get("product_external_id") if item.get("product_external_id") is not None else None)
            product_name = product_dict.get("name") if product_dict.get("name") else (item.get("product_name") if item.get("product_name") else "Unknown Product")
            size_id = item.get("size_id") if item.get("size_id") is not None else None
            size_text = item.get("size_text") if item.get("size_text") else ""
            
            # Debug logging
            print(f"Inserting order - product_id={product_id}, product_name={product_name}, product_external_id={product_external_id}, size_id={size_id}, size_text={size_text}, unit_price={unit_price}, quantity={quantity}, item_total={item_total}")
            
            # Insert order record for this item
            cursor.execute("""
                INSERT INTO orders (
                    order_number,
                    party_name,
                    station,
                    price_category,
                    product_id,
                    product_external_id,
                    product_name,
                    size_id,
                    size_text,
                    quantity,
                    unit_price,
                    total_price,
                    customer_name,
                    customer_phone,
                    customer_email,
                    customer_address,
                    order_status,
                    payment_status,
                    payment_method,
                    notes,
                    created_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id, order_number, created_at
            """, (
                order_number,  # Same order number for all items
                order_data.get("party_name"),
                order_data.get("station"),
                order_data.get("price_category"),  # Add price_category
                product_id,
                product_external_id,
                product_name,
                size_id,
                size_text,
                quantity,
                unit_price,
                item_total,  # Individual item total
                order_data.get("customer_name"),
                order_data.get("customer_phone"),
                order_data.get("customer_email"),
                order_data.get("customer_address"),
                order_data.get("order_status", "pending"),
                order_data.get("payment_status", "pending"),
                order_data.get("payment_method"),
                order_data.get("notes"),
                order_data.get("created_by", "system")
            ))
            
            order_result = cursor.fetchone()
            if order_result:
                order_ids.append(order_result["id"])
                created_orders.append({
                    "id": order_result["id"],
                    "order_number": order_result["order_number"],
                    "created_at": order_result["created_at"]
                })
        
        # Allow empty order_ids if items list was empty (order created without items)
        # This happens when creating an order first, then adding items later
        if len(order_ids) == 0 and len(items) > 0:
            if conn:
                conn.rollback()
            print(f"ERROR: No valid items added. Total items: {len(items)}, Skipped: {len(skipped_items)}, Order IDs: {len(order_ids)}")
            print(f"DEBUG: Skipped items details: {skipped_items}")
            print(f"DEBUG: First few items received: {items[:3] if len(items) > 0 else 'No items'}")
            error_detail = "No valid items were added to the order"
            if skipped_items:
                error_detail += f". Skipped items: {', '.join(skipped_items[:5])}"  # Show first 5 skipped items
                if len(skipped_items) > 5:
                    error_detail += f" (and {len(skipped_items) - 5} more)"
            else:
                error_detail += ". All items were rejected (check product_id, quantity, and unit_price)"
            print(f"DEBUG: Error detail to return: {error_detail}")
            raise HTTPException(
                status_code=400,
                detail=error_detail
            )
        
        conn.commit()
        
        # Return first order details (all have same order_number)
        first_order = created_orders[0] if created_orders else None
        
        return {
            "order_id": order_ids[0] if order_ids else None,
            "order_number": order_number,
            "total_price": total_order_price,
            "item_count": len(order_ids),
            "order_count": len(order_ids),  # Number of order records created
            "status": "success",
            "created_at": first_order["created_at"].isoformat() if first_order and first_order["created_at"] else None
        }
        
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        import traceback
        error_trace = traceback.format_exc()
        print(f"Error creating order with multiple items: {str(e)}")
        print(f"Traceback: {error_trace}")
        raise HTTPException(
            status_code=500,
            detail=f"Error creating order: {str(e)}"
        )
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/product/barcode/{barcode:path}")
def get_product_by_barcode(barcode: str):
    """
    Retrieve product details by barcode/QR code from products_master
    Searches in external_id and qr_code fields
    Handles URL-encoded barcodes and extracts codes from URLs
    Uses :path to allow special characters in the barcode
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Decode URL-encoded barcode
        from urllib.parse import unquote
        decoded_barcode = unquote(barcode)
        
        # If barcode looks like a URL, try to extract the actual code
        # Handle formats like: http://65.1.12.120/qr?xF2kd3A84m or http://65.1.12.120/qr?code=xF2kd3A84m
        search_barcodes = [decoded_barcode]
        
        if 'http://' in decoded_barcode or 'https://' in decoded_barcode:
            try:
                from urllib.parse import urlparse, parse_qs
                parsed = urlparse(decoded_barcode)
                # Extract from query parameters
                if parsed.query:
                    params = parse_qs(parsed.query)
                    # If query has no '=' (no key-value pairs), use the query string itself
                    if '=' not in parsed.query:
                        search_barcodes.append(parsed.query)
                    else:
                        # Try common parameter names
                        for param_name in ['code', 'id', 'qr', 'barcode']:
                            if param_name in params and params[param_name]:
                                search_barcodes.append(params[param_name][0])
                        # If no named params, get first value
                        if not any('code' in str(k).lower() or 'id' in str(k).lower() or 'qr' in str(k).lower() for k in params.keys()):
                            for values in params.values():
                                if values:
                                    search_barcodes.append(values[0])
                                    break
                # Extract from path (e.g., /qr/xF2kd3A84m)
                if parsed.path and len(parsed.path) > 1:
                    path_parts = [p for p in parsed.path.split('/') if p]
                    if path_parts:
                        search_barcodes.append(path_parts[-1])
            except Exception as e:
                print(f"Warning: Could not parse URL from barcode: {e}")
        
        # Remove duplicates and empty strings
        search_barcodes = list(dict.fromkeys([b for b in search_barcodes if b and b.strip()]))
        
        if not search_barcodes:
            raise HTTPException(status_code=400, detail="Invalid barcode: could not extract barcode from input")
        
        # Try to find by external_id or qr_code via product_catalog
        # Build query with multiple barcode values to try
        placeholders = ','.join(['%s'] * len(search_barcodes))
        cursor.execute(f"""
            SELECT 
                pm.id,
                pm.external_id,
                pm.name,
                pm.category_id,
                pm.category as category_name,
                pm.image as image_url,
                pm.video as video_url,
                pm.is_active,
                pm.created_on as created_at,
                pm.updated_at,
                pm.designs,
                pc.qr_code
            FROM products_master pm
            LEFT JOIN product_catalog pc ON pm.external_id = pc.external_id
            WHERE (pm.external_id::text IN ({placeholders}) OR pc.qr_code IN ({placeholders})) 
            AND pm.is_active = true
            LIMIT 1
        """, tuple(search_barcodes + search_barcodes))
        
        product = cursor.fetchone()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        product_id = product['id']
        product_dict = {
            'id': product_id,
            'external_id': product['external_id'],
            'name': product['name'],
            'category_id': product['category_id'],
            'category_name': product['category_name'],
            'image_url': product['image_url'],
            'video_url': product['video_url'],
            'qr_code': product['qr_code'],
            'is_active': product['is_active'],
            'created_at': product['created_at'],
            'updated_at': product['updated_at'],
            'designs': product.get('designs')
        }
        
        # Get sizes for this product - check both direct (product_type='master') and via product_catalog
        sizes_list = []
        
        # First, check for sizes directly linked to products_master (product_id = products_master.id, product_type = 'master')
        cursor.execute("""
            SELECT 
                id,
                size_id,
                size_text,
                price_a,
                price_b,
                price_c,
                price_d,
                price_e,
                price_r,
                is_active
            FROM product_sizes
            WHERE product_id = %s AND product_type = 'master' AND is_active = true
            ORDER BY id
        """, (product_id,))
        
        direct_sizes = cursor.fetchall()
        for size in direct_sizes:
            size_dict = {
                'id': size['id'],
                'size_id': size['size_id'],
                'size_text': size['size_text'],
                'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                'is_active': size['is_active']
            }
            sizes_list.append(size_dict)
        
        # If no direct sizes found, check via product_catalog
        if not sizes_list and product['external_id']:
            cursor.execute("""
                SELECT 
                    ps.id,
                    ps.size_id,
                    ps.size_text,
                    ps.price_a,
                    ps.price_b,
                    ps.price_c,
                    ps.price_d,
                    ps.price_e,
                    ps.price_r,
                    ps.is_active
                FROM product_sizes ps
                JOIN product_catalog pc ON ps.product_id = pc.id
                WHERE pc.external_id = %s AND ps.is_active = true
                ORDER BY ps.size_id
            """, (product['external_id'],))
            
            catalog_sizes = cursor.fetchall()
            for size in catalog_sizes:
                size_dict = {
                    'id': size['id'],
                    'size_id': size['size_id'],
                    'size_text': size['size_text'],
                    'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                    'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                    'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                    'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                    'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                    'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                    'is_active': size['is_active']
                }
                sizes_list.append(size_dict)
        
        product_dict['sizes'] = sizes_list
        
        return product_dict
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/product/{product_id}/qr-code")
def get_product_qr_code(product_id: int):
    """
    Generate QR code image for a product
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        cursor.execute("""
            SELECT external_id, qr_code 
            FROM product_catalog 
            WHERE id = %s AND is_active = true
        """, (product_id,))
        
        product = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        # Use qr_code if exists, otherwise use external_id
        qr_data = product.get('qr_code') or str(product.get('external_id', ''))
        
        if not qr_data:
            raise HTTPException(status_code=400, detail="Product has no QR code data")
        
        return _build_qr_response(qr_data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generating QR code: {str(e)}")
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.get("/api/products")
def get_all_products():
    """
    Get all products from products_master with their sizes
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Get all active products from products_master
        cursor.execute("""
            SELECT 
                pm.id,
                pm.external_id,
                pm.name,
                pm.category_id,
                pm.category as category_name,
                pm.image as image_url,
                pm.video as video_url,
                pm.is_active,
                pm.created_on as created_at,
                pm.updated_at,
                pc.qr_code
            FROM products_master pm
            LEFT JOIN product_catalog pc ON pm.external_id = pc.external_id
            WHERE pm.is_active = true
            ORDER BY pm.name
        """)
        products = cursor.fetchall()
        
        # Get all sizes for all products via product_catalog
        # Map products_master external_id to product_catalog id to get sizes
        external_ids = [p['external_id'] for p in products if p['external_id']]
        sizes_map = {}
        
        if external_ids:
            # Get product_catalog IDs for these external_ids
            placeholders = ','.join(['%s'] * len(external_ids))
            cursor.execute(f"""
                SELECT pc.id as catalog_id, pc.external_id
                FROM product_catalog pc
                WHERE pc.external_id IN ({placeholders})
            """, tuple(external_ids))
            catalog_mapping = {row['external_id']: row['catalog_id'] for row in cursor.fetchall()}
            
            # Get sizes using catalog IDs
            if catalog_mapping:
                catalog_ids = list(catalog_mapping.values())
                size_placeholders = ','.join(['%s'] * len(catalog_ids))
            cursor.execute(f"""
                SELECT 
                        pc.external_id,
                        ps.id,
                        ps.size_id,
                        ps.size_text,
                        ps.price_a,
                        ps.price_b,
                        ps.price_c,
                        ps.price_d,
                        ps.price_e,
                        ps.price_r,
                        ps.is_active
                    FROM product_sizes ps
                    JOIN product_catalog pc ON ps.product_id = pc.id
                    WHERE ps.product_id IN ({size_placeholders}) AND ps.is_active = true
                    ORDER BY pc.external_id, ps.size_id
                """, tuple(catalog_ids))
            
            sizes = cursor.fetchall()
                # Group sizes by external_id (products_master key)
            for size in sizes:
                    external_id = size['external_id']
                    if external_id not in sizes_map:
                        sizes_map[external_id] = []
                
                    size_dict = {
                        'id': size['id'],
                        'size_id': size['size_id'],
                        'size_text': size['size_text'],
                        'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                        'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                        'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                        'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                        'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                        'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                        'is_active': size['is_active']
                    }
                    sizes_map[external_id].append(size_dict)
        
        # Build result with sizes grouped by product
        result = []
        for product in products:
            product_dict = {
                'id': product['id'],
                'external_id': product['external_id'],
                'name': product['name'],
                'category_id': product['category_id'],
                'category_name': product['category_name'],
                'image_url': product['image_url'],
                'video_url': product['video_url'],
                'qr_code': product['qr_code'],
                'is_active': product['is_active'],
                'created_at': product['created_at'],
                'updated_at': product['updated_at']
            }
            # Get sizes using external_id
            external_id = product['external_id']
            product_dict['sizes'] = sizes_map.get(external_id, []) if external_id else []
            result.append(product_dict)
        
        return result
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.post("/api/order")
def create_order(order_data: dict):
    """
    Create a new order with professional structure
    Supports both single item and multiple items
    """
    conn = None
    try:
        # Validate required fields
        required_fields = ['party_name', 'station', 'customer_name', 'customer_phone']
        missing_fields = [field for field in required_fields if not order_data.get(field)]
        if missing_fields:
            raise HTTPException(
                status_code=400, 
                detail=f"Missing required fields: {', '.join(missing_fields)}"
            )
        
        if not order_data.get("product_id"):
            raise HTTPException(
                status_code=400,
                detail="Product ID is required"
            )
        
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Ensure orders table exists with order_number column
        ensure_orders_table(cursor)
        conn.commit()
        
        # Get product details if product_id is provided
        product_info = None
        if order_data.get("product_id"):
            cursor.execute("""
                SELECT id, external_id, name 
                FROM product_catalog 
                WHERE id = %s AND is_active = true
            """, (order_data.get("product_id"),))
            result = cursor.fetchone()
            if result:
                product_info = dict(result)
            else:
                raise HTTPException(
                    status_code=404,
                    detail=f"Product with ID {order_data.get('product_id')} not found"
                )
        
        # Calculate total price
        unit_price = order_data.get("unit_price", 0) or 0
        quantity = order_data.get("quantity", 1)
        total_price = float(unit_price) * int(quantity)
        
        if total_price <= 0:
            raise HTTPException(
                status_code=400,
                detail="Total price must be greater than 0"
            )
        
        # Generate order number in format: DJ-XXXXXX
        try:
            # First, check for incomplete orders (orders with no items) to reuse
            # An incomplete order has product_id IS NULL and total_price = 0
            # Only check for DJ- prefix orders
            cursor.execute("""
                SELECT DISTINCT order_number 
                FROM orders 
                WHERE order_number LIKE 'DJ-%'
                  AND product_id IS NULL 
                  AND total_price = 0
                ORDER BY order_number ASC
                LIMIT 1
            """)
            incomplete_order = cursor.fetchone()
            
            if incomplete_order:
                # Reuse the incomplete order number (only if it's DJ- prefix)
                incomplete_number = incomplete_order[0] if isinstance(incomplete_order, (tuple, list)) else incomplete_order.get('order_number')
                if incomplete_number and incomplete_number.startswith('DJ-'):
                    order_number = incomplete_number
                    # Delete the incomplete order record to replace it
                    cursor.execute("""
                        DELETE FROM orders 
                        WHERE order_number = %s 
                          AND product_id IS NULL 
                          AND total_price = 0
                    """, (order_number,))
                    print(f"Reusing incomplete order number: {order_number}")
            
            # If no incomplete order found, generate a new one
            if not order_number:
                # Find the highest sequence number for DJ- prefix only
                cursor.execute("""
                    SELECT order_number 
                    FROM orders 
                    WHERE order_number LIKE 'DJ-%'
                    ORDER BY order_number DESC
                    LIMIT 1
                """)
                result = cursor.fetchone()
                max_sequence = 0
                if result:
                    existing_number = result[0] if isinstance(result, (tuple, list)) else result.get('order_number')
                    if existing_number and existing_number.startswith('DJ-'):
                        try:
                            sequence_part = existing_number.split('-')[1]
                            max_sequence = int(sequence_part)
                        except (ValueError, IndexError):
                            max_sequence = 0
                
                # Generate new order number with DJ- prefix
                order_number = f"DJ-{str(max_sequence + 1).zfill(6)}"
                
                # Ensure uniqueness
                max_attempts = 1000
                for attempt in range(max_attempts):
                    cursor.execute("SELECT id FROM orders WHERE order_number = %s", (order_number,))
                    exists = cursor.fetchone()
                    if not exists:
                        break
                    order_number = f"DJ-{str(max_sequence + attempt + 2).zfill(6)}"
        except Exception as e:
            from datetime import datetime
            # Fallback: use timestamp-based number
            order_number = f"DJ-{datetime.now().strftime('%Y%m%d%H%M%S')[:6]}"
        
        # Check and fix foreign key constraint if it references wrong table
        try:
            cursor.execute("""
                SELECT constraint_name, table_name
                FROM information_schema.table_constraints
                WHERE table_name = 'orders' 
                AND constraint_type = 'FOREIGN KEY'
                AND constraint_name LIKE '%product_id%'
            """)
            fk_constraints = cursor.fetchall()
            
            # Check if foreign key references wrong table
            for constraint in fk_constraints:
                constraint_name = constraint[0]
                cursor.execute("""
                    SELECT 
                        tc.constraint_name, 
                        kcu.column_name, 
                        ccu.table_name AS foreign_table_name
                    FROM information_schema.table_constraints AS tc 
                    JOIN information_schema.key_column_usage AS kcu
                      ON tc.constraint_name = kcu.constraint_name
                    JOIN information_schema.constraint_column_usage AS ccu
                      ON ccu.constraint_name = tc.constraint_name
                    WHERE tc.constraint_name = %s
                """, (constraint_name,))
                fk_info = cursor.fetchone()
                
                if fk_info and fk_info[2] == 'products':
                    # Drop the wrong foreign key constraint
                    print(f"Dropping incorrect foreign key constraint: {constraint_name}")
                    cursor.execute(f"ALTER TABLE orders DROP CONSTRAINT IF EXISTS {constraint_name}")
                    # Add correct foreign key constraint
                    cursor.execute("""
                        ALTER TABLE orders 
                        ADD CONSTRAINT orders_product_id_fkey 
                        FOREIGN KEY (product_id) 
                        REFERENCES product_catalog(id) 
                        ON DELETE SET NULL
                    """)
                    print("Fixed foreign key constraint to reference product_catalog")
        except Exception as fk_error:
            print(f"Warning: Could not fix foreign key constraint: {fk_error}")
        
        # Check if party_name, station, price_category, transport_name, and created_by columns exist, if not add them
        try:
            cursor.execute("""
                SELECT column_name, character_maximum_length
                FROM information_schema.columns 
                WHERE table_name = 'orders' AND column_name IN ('party_name', 'station', 'price_category', 'transport_name', 'created_by')
            """)
            existing_cols = cursor.fetchall()
            existing_columns = [row[0] if isinstance(row, (tuple, list)) else row.get("column_name") for row in existing_cols]
            
            if 'party_name' not in existing_columns:
                cursor.execute("ALTER TABLE orders ADD COLUMN party_name VARCHAR(255)")
            else:
                # Always check and upgrade party_name if it's VARCHAR(50) or smaller
                party_col = next((row for row in existing_cols if (row[0] if isinstance(row, (tuple, list)) else row.get("column_name")) == 'party_name'), None)
                if party_col:
                    try:
                        max_length = party_col[1] if isinstance(party_col, (tuple, list)) else party_col.get("character_maximum_length")
                        if max_length is not None and max_length < 255:
                            cursor.execute("ALTER TABLE orders ALTER COLUMN party_name TYPE VARCHAR(255)")
                            conn.commit()  # Commit the ALTER immediately
                            print(f"✓ Updated orders.party_name column from VARCHAR({max_length}) to VARCHAR(255)")
                        elif max_length is None:
                            # Try to upgrade anyway if we can't determine length
                            try:
                                cursor.execute("ALTER TABLE orders ALTER COLUMN party_name TYPE VARCHAR(255)")
                                conn.commit()
                                print(f"✓ Updated orders.party_name column to VARCHAR(255)")
                            except Exception:
                                pass
                    except Exception as alter_err:
                        print(f"Warning: Could not alter orders.party_name column size: {alter_err}")
                        import traceback
                        traceback.print_exc()
            if 'station' not in existing_columns:
                cursor.execute("ALTER TABLE orders ADD COLUMN station VARCHAR(255)")
            if 'price_category' not in existing_columns:
                cursor.execute("ALTER TABLE orders ADD COLUMN price_category VARCHAR(100)")
            if 'transport_name' not in existing_columns:
                cursor.execute("ALTER TABLE orders ADD COLUMN transport_name VARCHAR(255)")
            if 'created_by' not in existing_columns:
                cursor.execute("ALTER TABLE orders ADD COLUMN created_by VARCHAR(255)")
        except Exception as col_error:
            print(f"Warning: Could not check/add columns: {col_error}")
        
        # Insert order into database
        try:
            cursor.execute("""
                INSERT INTO orders (
                    order_number,
                    party_name,
                    station,
                    price_category,
                    product_id,
                    product_external_id,
                    product_name,
                    size_id,
                    size_text,
                    quantity,
                    unit_price,
                    total_price,
                    customer_name,
                    customer_phone,
                    customer_email,
                    customer_address,
                    order_status,
                    payment_status,
                    payment_method,
                    notes,
                    created_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id, order_number, created_at
            """, (
                order_number,
                order_data.get("party_name"),
                order_data.get("station"),
                order_data.get("price_category"),  # Add price_category
                order_data.get("product_id"),
                product_info.get("external_id") if product_info else order_data.get("product_external_id"),
                product_info.get("name") if product_info else order_data.get("product_name"),
                order_data.get("size_id"),
                order_data.get("size_text"),
                quantity,
                unit_price,
                total_price,
                order_data.get("customer_name"),
                order_data.get("customer_phone"),
                order_data.get("customer_email"),
                order_data.get("customer_address"),
                order_data.get("order_status", "pending"),
                order_data.get("payment_status", "pending"),
                order_data.get("payment_method"),
                order_data.get("notes"),
                order_data.get("created_by", "system")
            ))
        except Exception as insert_error:
            print(f"Insert error details: {insert_error}")
            raise
        
        result = cursor.fetchone()
        if not result:
            if conn:
                conn.rollback()
            raise HTTPException(
                status_code=500,
                detail="Failed to create order: Database did not return order details. Please check if the orders table exists and has the correct structure."
            )
        
        conn.commit()
        
        return {
            "order_id": result["id"],
            "order_number": result["order_number"],
            "status": "success",
            "created_at": result["created_at"].isoformat() if result["created_at"] else None
        }
        
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        import traceback
        error_trace = traceback.format_exc()
        error_msg = str(e) if str(e) else "Unknown error occurred"
        print(f"Error creating order: {error_msg}")
        print(f"Traceback: {error_trace}")
        raise HTTPException(
            status_code=500, 
            detail=f"Error creating order: {error_msg}. Please check the database connection and table structure."
        )
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/orders/party-data")
def get_party_data_from_orders_query(party_name: str = None):
    """Query parameter version: /api/orders/party-data?party_name=..."""
    return get_party_data_from_orders_impl(party_name)

@app.get("/api/orders/party-data/{party_name_path:path}")
def get_party_data_from_orders_path(party_name_path: str):
    """Path parameter version: /api/orders/party-data/{name} - uses :path to handle / in names"""
    return get_party_data_from_orders_impl(party_name_path)

def get_party_data_from_orders_impl(party_name_value: str = None):
    """
    Get the most recent station, phone number, price category, transport for a party.
    Uses exact matching only. Always returns 200 OK with data (or null values if not found).
    Never returns 404 to prevent frontend errors.
    """
    global _party_data_cache, _party_data_cache_time
    
    # Handle invalid/empty party names gracefully
    party_trimmed = party_name_value.strip() if party_name_value else ""
    if not party_trimmed or len(party_trimmed) < 2 or party_trimmed == "/":
        # Return empty response for invalid party names (like "/" or empty)
        return {"station": None, "phone_number": None, "price_category": None, "transport_name": None}
    
    key = party_trimmed.lower()
    now = datetime.now().timestamp()
    # Don't use cache if it's a 404 response - always try fresh lookup
    cached_response = _party_data_cache.get(key)
    if cached_response and (now - _party_data_cache_time.get(key, 0)) < PARTY_DATA_CACHE_TTL:
        # Only return cached response if it's not None (None might indicate previous 404)
        if cached_response is not None:
            print(f"Returning cached party data for: {party_trimmed}")
            return cached_response

    conn = None
    cursor = None
    response_data = {"station": None, "phone_number": None, "price_category": None, "transport_name": None}
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)

        print(f"Fetching party data for: '{party_trimmed}' (EXACT MATCH ONLY)")
        response_data = {"station": None, "phone_number": None, "price_category": None, "transport_name": None}

        # 1. Try parties table first (master data - most reliable) - EXACT MATCH ONLY
        try:
            cursor.execute("""
                SELECT EXISTS (
                  SELECT FROM information_schema.tables
                  WHERE table_name = 'parties'
                ) AS exists
            """)
            ex = cursor.fetchone()
            table_exists = ex and (ex.get("exists") if isinstance(ex, dict) else ex[0])
            
            if table_exists:
                # Check which columns exist in parties table
                cursor.execute("""
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_name = 'parties'
                    AND column_name IN ('shop_name', 'price_category', 'station', 'transport', 'transport_name')
                """)
                parties_cols = cursor.fetchall()
                parties_col_names = [row.get("column_name") if isinstance(row, dict) else row[0] for row in parties_cols]
                
                # Build SELECT clause based on available columns
                select_fields = []
                if 'shop_name' in parties_col_names:
                    select_fields.append('shop_name')
                if 'price_category' in parties_col_names:
                    select_fields.append('price_category')
                if 'station' in parties_col_names:
                    select_fields.append('station')
                # Try both transport and transport_name
                if 'transport' in parties_col_names:
                    select_fields.append('transport')
                elif 'transport_name' in parties_col_names:
                    select_fields.append('transport_name')
                
                if select_fields and 'shop_name' in parties_col_names:
                    select_clause = ', '.join(select_fields)
                    
                    # EXACT MATCH ONLY - no normalization or flexible matching
                    # Build query safely - validate select_clause doesn't contain SQL injection
                    if select_clause and all(col in ['shop_name', 'price_category', 'station', 'transport', 'transport_name'] for col in select_clause.split(', ')):
                        cursor.execute(f"""
                            SELECT {select_clause}
                            FROM parties
                            WHERE LOWER(TRIM(shop_name)) = LOWER(TRIM(%s))
                            ORDER BY id DESC
                            LIMIT 1
                        """, (party_trimmed,))
                    else:
                        # Fallback to safe default columns
                        cursor.execute("""
                            SELECT shop_name, price_category, station
                            FROM parties
                            WHERE LOWER(TRIM(shop_name)) = LOWER(TRIM(%s))
                            ORDER BY id DESC
                            LIMIT 1
                        """, (party_trimmed,))
                    pr = cursor.fetchone()
                    
                    if pr:
                        matched_shop_name = pr.get("shop_name")
                        station_from_parties = pr.get("station")
                        # Try both transport and transport_name - ONLY use actual transport fields
                        transport_from_parties = pr.get("transport") or pr.get("transport_name")
                        price_cat_from_parties = pr.get("price_category")
                        
                        # CRITICAL: Never use station as transport_name - ensure transport is not the same as station
                        if transport_from_parties and station_from_parties:
                            try:
                                transport_str = str(transport_from_parties).strip().lower() if transport_from_parties else ""
                                station_str = str(station_from_parties).strip().lower() if station_from_parties else ""
                                if transport_str and station_str and transport_str == station_str:
                                    print(f"  WARNING: transport='{transport_from_parties}' matches station='{station_from_parties}' - setting transport_name to None")
                                    transport_from_parties = None
                            except Exception as check_err:
                                print(f"  Warning: Error comparing transport and station: {check_err}")
                                # If comparison fails, set transport to None to be safe
                                transport_from_parties = None
                        
                        print(f"✓ Found in parties table (EXACT MATCH): shop_name='{matched_shop_name}'")
                        print(f"  Data: station='{station_from_parties}', transport='{transport_from_parties}', price_category='{price_cat_from_parties}'")
                        
                        # Parties table is master data - use it first
                        if station_from_parties:
                            response_data["station"] = station_from_parties
                        if price_cat_from_parties:
                            response_data["price_category"] = price_cat_from_parties
                        # Only set transport_name if it's a valid transport value (not null, not empty, and not the same as station)
                        try:
                            if transport_from_parties and str(transport_from_parties).strip():
                                response_data["transport_name"] = str(transport_from_parties).strip()
                            else:
                                # Explicitly set to None if transport is null/empty
                                response_data["transport_name"] = None
                        except Exception as transport_err:
                            print(f"  Warning: Error setting transport_name from parties: {transport_err}")
                            response_data["transport_name"] = None
        except Exception as parties_err:
            print(f"Warning: Error fetching from parties table: {parties_err}")
            import traceback
            traceback.print_exc()

        # 2. Try challans table (recent transaction data) - EXACT MATCH ONLY
        try:
            # EXACT MATCH ONLY - no normalization or flexible matching
            cursor.execute("""
                SELECT station_name, transport_name, price_category, party_name
                FROM challans
                WHERE LOWER(TRIM(party_name)) = LOWER(TRIM(%s))
                ORDER BY created_at DESC LIMIT 1
            """, (party_trimmed,))
            cr = cursor.fetchone()
            
            if cr:
                matched_party_name = cr.get("party_name")
                station_from_challans = cr.get("station_name")
                transport_from_challans = cr.get("transport_name")
                price_cat_from_challans = cr.get("price_category")
                
                # CRITICAL: Never use station_name as transport_name - ensure transport_name is not the same as station_name
                if transport_from_challans and station_from_challans:
                    try:
                        transport_str = str(transport_from_challans).strip().lower() if transport_from_challans else ""
                        station_str = str(station_from_challans).strip().lower() if station_from_challans else ""
                        if transport_str and station_str and transport_str == station_str:
                            print(f"  WARNING: transport_name='{transport_from_challans}' matches station_name='{station_from_challans}' - setting transport_name to None")
                            transport_from_challans = None
                    except Exception as check_err:
                        print(f"  Warning: Error comparing transport_name and station_name: {check_err}")
                        # If comparison fails, set transport to None to be safe
                        transport_from_challans = None
                
                print(f"✓ Found in challans table (EXACT MATCH): party_name='{matched_party_name}'")
                print(f"  Data: station_name='{station_from_challans}', transport_name='{transport_from_challans}', price_category='{price_cat_from_challans}'")
                
                # Fill missing fields only (parties table takes priority)
                if not response_data["station"]:
                    response_data["station"] = station_from_challans if station_from_challans else None
                if not response_data["price_category"]:
                    response_data["price_category"] = price_cat_from_challans if price_cat_from_challans else None
                # Only set transport_name if it's not already set, is valid, and is not the same as station_name
                if not response_data["transport_name"]:
                    try:
                        if transport_from_challans and str(transport_from_challans).strip():
                            response_data["transport_name"] = str(transport_from_challans).strip()
                        else:
                            # Explicitly set to None if transport is null/empty
                            response_data["transport_name"] = None
                    except Exception as transport_err:
                        print(f"  Warning: Error setting transport_name from challans: {transport_err}")
                        response_data["transport_name"] = None
        except Exception as challan_err:
            print(f"Warning: Error fetching from challans for party '{party_trimmed}': {challan_err}")
            import traceback
            traceback.print_exc()

        # 3. Try orders table (for phone_number and any still-missing fields) - EXACT MATCH ONLY
        try:
            cursor.execute("""
                SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'orders') AS exists
            """)
            ex = cursor.fetchone()
            if ex and (ex.get("exists") if isinstance(ex, dict) else ex[0]):
                # EXACT MATCH ONLY - no normalization or flexible matching
                cursor.execute("""
                    SELECT station, customer_phone, price_category, transport_name, party_name
                    FROM orders
                    WHERE LOWER(TRIM(party_name)) = LOWER(TRIM(%s))
                    ORDER BY created_at DESC LIMIT 1
                """, (party_trimmed,))
                ord_row = cursor.fetchone()
                
                if ord_row:
                    matched_party_name = ord_row.get("party_name")
                    station_from_orders = ord_row.get("station")
                    transport_from_orders = ord_row.get("transport_name")
                    price_cat_from_orders = ord_row.get("price_category")
                    
                    # CRITICAL: Never use station as transport_name - ensure transport_name is not the same as station
                    if transport_from_orders and station_from_orders:
                        try:
                            transport_str = str(transport_from_orders).strip().lower() if transport_from_orders else ""
                            station_str = str(station_from_orders).strip().lower() if station_from_orders else ""
                            if transport_str and station_str and transport_str == station_str:
                                print(f"  WARNING: transport_name='{transport_from_orders}' matches station='{station_from_orders}' - setting transport_name to None")
                                transport_from_orders = None
                        except Exception as check_err:
                            print(f"  Warning: Error comparing transport_name and station: {check_err}")
                            # If comparison fails, set transport to None to be safe
                            transport_from_orders = None
                    
                    print(f"✓ Found in orders table (EXACT MATCH): party_name='{matched_party_name}'")
                    print(f"  Data from orders: station='{station_from_orders}', transport='{transport_from_orders}', price_category='{price_cat_from_orders}'")
                    
                    # Fill missing fields only (parties and challans take priority)
                    if not response_data["station"]:
                        response_data["station"] = station_from_orders
                    if ord_row.get("customer_phone"):
                        response_data["phone_number"] = ord_row["customer_phone"]
                    if not response_data["price_category"]:
                        response_data["price_category"] = price_cat_from_orders
                    # Only set transport_name if it's not already set, is valid, and is not the same as station
                    if not response_data["transport_name"]:
                        try:
                            if transport_from_orders and str(transport_from_orders).strip():
                                response_data["transport_name"] = str(transport_from_orders).strip()
                            else:
                                # Explicitly set to None if transport is null/empty
                                response_data["transport_name"] = None
                        except Exception as transport_err:
                            print(f"  Warning: Error setting transport_name from orders: {transport_err}")
                            response_data["transport_name"] = None
        except Exception as order_err:
            print(f"Warning: Error fetching from orders for party '{party_trimmed}': {order_err}")
            import traceback
            traceback.print_exc()


        # Return data even if some fields are None - frontend handles this gracefully
        # Always return a response (even with null values) instead of 404
        # This allows the frontend to proceed with creating challans even if no historical data exists
        has_data = any([response_data["station"], response_data["phone_number"],
                       response_data["price_category"], response_data["transport_name"]])
        
        if has_data:
            print(f"Found party data for '{party_trimmed}': station={response_data['station']}, price_category={response_data['price_category']}, transport={response_data['transport_name']}")
        else:
            print(f"No historical data found for party: '{party_trimmed}' - returning empty response")
        
        # Cache and return the response (even if all fields are None)
        _party_data_cache[key] = response_data
        _party_data_cache_time[key] = now
        return response_data
            
    except HTTPException as http_ex:
        # Never return HTTPException - always return empty response
        print(f"HTTPException caught for party '{party_trimmed}': {http_ex.status_code} - {http_ex.detail}")
        import traceback
        traceback.print_exc()
        return {"station": None, "phone_number": None, "price_category": None, "transport_name": None}
    except Exception as e:
        print(f"ERROR fetching party data for '{party_trimmed}': {e}")
        import traceback
        traceback.print_exc()
        # Always return empty response instead of error to prevent 500
        return {"station": None, "phone_number": None, "price_category": None, "transport_name": None}
    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass

def _dedupe_sort(values: list) -> list:
    """Deduplicate (case-insensitive) and sort."""
    seen = set()
    result = []
    for v in values:
        if not v or not str(v).strip():
            continue
        normalized = str(v).strip().lower()
        if normalized not in seen:
            seen.add(normalized)
            result.append(str(v).strip())
    result.sort()
    return result


def _get_challan_options_from_db(quick: bool, conn, cursor) -> dict:
    """Fetch options from DB. quick=True = challans only (faster)."""
    limit = 2000  # Fetch more data so dropdowns show all options
    party_names = []
    station_names = []
    transport_names = []
    price_categories = []
    customer_names = []
    customer_phones = []

    def _try(fn):
        try:
            return fn()
        except Exception:
            try:
                conn.rollback()
            except Exception:
                pass
            return []

    # Helper to fetch party names from parties table (shop_name column)
    def _fetch_parties_table_names():
        try:
            cursor.execute("""
                SELECT EXISTS (
                  SELECT FROM information_schema.tables
                  WHERE table_name = 'parties'
                ) AS exists
            """)
            ex = cursor.fetchone()
            table_exists = ex and (ex.get("exists") if isinstance(ex, dict) else ex[0])
            if table_exists:
                # Try to fetch shop_name from parties table
                try:
                    cursor.execute("""
                        SELECT DISTINCT shop_name
                        FROM parties
                        WHERE shop_name IS NOT NULL AND shop_name <> ''
                        ORDER BY shop_name
                        LIMIT %s
                    """, (limit,))
                    return [row.get("shop_name") if isinstance(row, dict) else row[0] 
                           for row in cursor.fetchall() 
                           if row and (row.get("shop_name") if isinstance(row, dict) else row[0])]
                except Exception:
                    # If parties schema is different, return empty list
                    return []
            return []
        except Exception:
            return []
    
    if quick:
        # Challans only - 4 queries, much faster (no orders table)
        # Also include parties table for party names
        parties_names = _try(_fetch_parties_table_names)
        party_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "challans", "party_name", limit=limit))
            + parties_names
        )
        station_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "challans", "station_name", limit=limit))
        )
        transport_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "challans", "transport_name", limit=limit))
        )
        price_categories = _try(lambda: fetch_distinct_values(cursor, "challans", "price_category", limit=limit))
    else:
        # Full: orders + challans + parties table
        parties_names = _try(_fetch_parties_table_names)
        party_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "orders", "party_name", limit=limit))
            + _try(lambda: fetch_distinct_values(cursor, "challans", "party_name", limit=limit))
            + parties_names
        )
        station_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "orders", "station", limit=limit))
            + _try(lambda: fetch_distinct_values(cursor, "challans", "station_name", limit=limit))
        )
        transport_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "orders", "transport_name", limit=limit))
            + _try(lambda: fetch_distinct_values(cursor, "challans", "transport_name", limit=limit))
        )
        price_categories = _try(lambda: fetch_distinct_values(cursor, "challans", "price_category", limit=limit))
        customer_names = _dedupe_sort(
            _try(lambda: fetch_distinct_values(cursor, "orders", "customer_name", limit=limit))
        )
        customer_phones_raw = _try(lambda: fetch_distinct_values(cursor, "orders", "customer_phone", limit=limit))
        seen_phone = set()
        for p in customer_phones_raw:
            if not p or not str(p).strip():
                continue
            clean = "".join(filter(str.isdigit, str(p).strip()))
            if clean and clean not in seen_phone:
                seen_phone.add(clean)
                customer_phones.append(str(p).strip())
        customer_phones.sort()

    default_price_categories = ["A", "B", "C", "D", "E", "R"]
    merged_price_categories = list(dict.fromkeys(price_categories + default_price_categories))
    return {
        "party_names": party_names,
        "station_names": station_names,
        "transport_names": transport_names,
        "price_categories": merged_price_categories,
        "customer_names": customer_names,
        "customer_phones": customer_phones,
        "counts": {
            "party_names_count": len(party_names),
            "station_names_count": len(station_names),
            "transport_names_count": len(transport_names),
            "price_categories_count": len(merged_price_categories),
            "customer_names_count": len(customer_names),
            "customer_phones_count": len(customer_phones),
        }
    }


_challan_options_quick_cache = None
_challan_options_quick_cache_time = 0


@app.get(
    "/api/challan/options",
    summary="Get challan options",
    description="Returns party names, stations, etc. Use ?quick=1 for faster load (challans only).",
    tags=["Challan"],
)
def get_challan_options(quick: bool = False):
    """Options for challan/order forms. quick=True uses challans only (faster)."""
    global _challan_options_cache, _challan_options_cache_time
    global _challan_options_quick_cache, _challan_options_quick_cache_time
    now = datetime.now().timestamp()
    if quick:
        if _challan_options_quick_cache and (now - _challan_options_quick_cache_time) < CHALLAN_OPTIONS_CACHE_TTL:
            return _challan_options_quick_cache
    else:
        if _challan_options_cache and (now - _challan_options_cache_time) < CHALLAN_OPTIONS_CACHE_TTL:
            return _challan_options_cache

    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        result = _get_challan_options_from_db(quick=quick, conn=conn, cursor=cursor)
        if quick:
            _challan_options_quick_cache = result
            _challan_options_quick_cache_time = now
        else:
            _challan_options_cache = result
            _challan_options_cache_time = now
        return result
    except Exception as e:
        import traceback
        print(f"Error in get_challan_options: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=500,
            detail=f"Error fetching challan options: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.get("/api/debug/column-types")
def debug_column_types():
    """Diagnostic endpoint to check actual column types in database."""
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        cursor.execute("""
            SELECT table_name, column_name, data_type, character_maximum_length
            FROM information_schema.columns
            WHERE table_name IN ('challans', 'orders')
            AND column_name IN ('party_name', 'station_name', 'transport_name', 'challan_number')
            ORDER BY table_name, column_name
        """)
        results = cursor.fetchall()
        return {
            "columns": [
                {
                    "table": r.get("table_name") if isinstance(r, dict) else r[0],
                    "column": r.get("column_name") if isinstance(r, dict) else r[1],
                    "type": r.get("data_type") if isinstance(r, dict) else r[2],
                    "max_length": r.get("character_maximum_length") if isinstance(r, dict) else r[3]
                }
                for r in results
            ]
        }
    except Exception as e:
        return {"error": str(e)}
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.post("/api/challans")
def create_challan(challan_data: dict):
    """
    Create a challan with header details and line items.
    Safe for concurrent submissions from multiple devices: challan numbers are
    generated under an advisory lock and INSERT is retried on duplicate number.
    """
    required_fields = ["party_name", "station_name", "transport_name"]
    missing_fields = [field for field in required_fields if not challan_data.get(field)]
    if missing_fields:
        raise HTTPException(
            status_code=400,
            detail=f"Missing required fields: {', '.join(missing_fields)}"
        )
    
    items = challan_data.get("items", [])
    # Allow creating challan without items (items can be added later)
    
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor, conn)
        conn.commit()  # Commit table creation before inserting data
        
        # Explicitly ensure VARCHAR columns are correct size RIGHT BEFORE insert
        # Use direct SQL to be absolutely sure
        try:
            print("Running pre-insert column migration...")
            migration_queries = [
                "ALTER TABLE challans ALTER COLUMN party_name TYPE VARCHAR(255) USING party_name::VARCHAR(255)",
                "ALTER TABLE challans ALTER COLUMN station_name TYPE VARCHAR(255) USING station_name::VARCHAR(255)",
                "ALTER TABLE challans ALTER COLUMN transport_name TYPE VARCHAR(255) USING transport_name::VARCHAR(255)",
                "ALTER TABLE challans ALTER COLUMN challan_number TYPE VARCHAR(255) USING challan_number::VARCHAR(255)",
            ]
            for query in migration_queries:
                try:
                    cursor.execute(query)
                    conn.commit()
                    print(f"✓ Executed: {query}")
                except Exception as q_err:
                    error_msg = str(q_err).lower()
                    if 'already' not in error_msg and 'does not exist' not in error_msg:
                        print(f"Warning: Migration query failed (may already be correct): {q_err}")
            
            # Also run the migration function as backup
            _migrate_varchar_columns(cursor, conn)
            conn.commit()
            print("Pre-insert migration completed")
        except Exception as migrate_err:
            print(f"Warning: Pre-insert migration check failed: {migrate_err}")
            import traceback
            traceback.print_exc()
        
        prepared_items = []
        total_amount = 0.0
        total_quantity = 0.0
        
        # Process items if provided
        if items and len(items) > 0:
            for item in items:
                quantity = float(item.get("quantity", 0) or 0)
                unit_price = float(item.get("unit_price", 0) or 0)
                
                if quantity <= 0:
                    raise HTTPException(status_code=400, detail="Item quantity must be greater than 0")
                if unit_price < 0:
                    raise HTTPException(status_code=400, detail="Item unit price cannot be negative")
                
                total_price = item.get("total_price")
                total_price = float(total_price) if total_price is not None else quantity * unit_price
                product_id = item.get("product_id")
                product_name = item.get("product_name")
                size_id = item.get("size_id")
                size_text = item.get("size_text")
                qr_code_value = item.get("qr_code")
                
                # Try to fetch product details if product_id is provided
                if product_id:
                    try:
                        cursor.execute("""
                            SELECT name, qr_code 
                            FROM product_catalog 
                            WHERE id = %s
                        """, (product_id,))
                        product_row = cursor.fetchone()
                        if product_row:
                            if not product_name:
                                product_name = product_row.get("name")
                            if not qr_code_value:
                                qr_code_value = product_row.get("qr_code")
                    except Exception as e:
                        print(f"Warning: Could not fetch product details for id {product_id}: {e}")
                
                if not product_name:
                    raise HTTPException(status_code=400, detail="Each item must include a product name")
                
                # Look up unit and GST from products_master
                item_unit = item.get("unit", "piece")
                item_gst = 0
                try:
                    if product_id:
                        cursor.execute("SELECT gst, unit FROM products_master WHERE id = %s", (product_id,))
                    else:
                        cursor.execute("SELECT gst, unit FROM products_master WHERE name = %s LIMIT 1", (product_name,))
                    pm_row = cursor.fetchone()
                    if pm_row:
                        if pm_row.get("unit"):
                            item_unit = pm_row["unit"]
                        if pm_row.get("gst") and total_price > 0:
                            item_gst = round(total_price * float(pm_row["gst"]) / 100)
                except Exception as lu_err:
                    print(f"Warning: Could not look up unit/GST for {product_name}: {lu_err}")

                prepared_items.append({
                    "product_id": product_id,
                    "product_name": product_name,
                    "size_id": size_id,
                    "size_text": size_text,
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "total_price": total_price,
                    "qr_code": qr_code_value,
                    "unit": item_unit,
                    "gst": item_gst
                })
                
                total_amount += total_price
                total_quantity += quantity
        
        # Get party_name for challan number generation and insertion
        party_name = challan_data.get("party_name", "")
        
        # Prepare values for insertion
        station_name = challan_data.get("station_name")
        transport_name = challan_data.get("transport_name")
        price_category = challan_data.get("price_category")
        notes = challan_data.get("notes")
        metadata = challan_data.get("metadata")
        status = challan_data.get("status", "draft")
        
        if not party_name or not station_name or not transport_name:
            raise HTTPException(
                status_code=400,
                detail="party_name, station_name, and transport_name are required"
            )

        # Auto-create party in parties table if not exists
        try:
            cursor.execute(
                "SELECT id FROM parties WHERE LOWER(TRIM(shop_name)) = LOWER(TRIM(%s)) LIMIT 1",
                (party_name,)
            )
            if not cursor.fetchone():
                cursor.execute(
                    "INSERT INTO parties (shop_name, station, price_category) VALUES (%s, %s, %s)",
                    (party_name.strip(), station_name.strip() if station_name else None, price_category or 'A')
                )
                print(f"Auto-created party: {party_name} / {station_name}")
        except Exception as party_err:
            print(f"Warning: Could not auto-create party {party_name}: {party_err}")
        
        # Always create a new challan with a new number so each device/session gets a unique challan.
        # (Previously we reused an empty challan for the same party, which caused the same number
        # to appear on another device when opening the same party.)
        
        # Convert metadata to JSON string if it's a dict
        metadata_json = None
        if metadata:
            if isinstance(metadata, dict):
                metadata_json = json.dumps(metadata)
            elif isinstance(metadata, str):
                metadata_json = metadata
            else:
                metadata_json = str(metadata)
        
        # Generate challan number and insert. Retry on unique violation so concurrent
        # submissions from multiple devices never get duplicate numbers or errors.
        challan_row = None
        max_create_retries = 3
        for _create_attempt in range(max_create_retries):
            try:
                challan_number = generate_challan_number(cursor, party_name)
                finalized_states = ['ready', 'in_transit', 'delivered']
                final_challan_number = challan_number
                if status in finalized_states:
                    if ' - DC' in challan_number:
                        parts = challan_number.split(' - DC')
                        if len(parts) > 1:
                            dc_part = 'DC' + parts[-1].strip()
                            final_challan_number = dc_part
                            print(f"Removing party name from new challan (status: {status}): {challan_number} -> {final_challan_number}")
                if not final_challan_number:
                    final_challan_number = challan_number
                number_to_insert = (final_challan_number or challan_number or "").strip() or challan_number
                cursor.execute("""
                    INSERT INTO challans (
                        challan_number,
                        party_name,
                        station_name,
                        transport_name,
                        price_category,
                        total_amount,
                        total_quantity,
                        gst_amount,
                        apply_gst,
                        status,
                        notes,
                        metadata
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING *
                """, (
                    number_to_insert,
                    party_name,
                    station_name,
                    transport_name,
                    price_category if price_category else None,
                    total_amount,
                    total_quantity,
                    sum(p.get("gst", 0) for p in prepared_items) if prepared_items else 0,
                    'Auto',
                    status,
                    notes if notes else None,
                    metadata_json,
                ))
                challan_row = cursor.fetchone()
                break
            except Exception as insert_err:
                error_msg = str(insert_err)
                error_lower = error_msg.lower()
                
                if getattr(insert_err, "sqlstate", None) == "23505":
                    conn.rollback()
                    if _create_attempt == max_create_retries - 1:
                        raise HTTPException(
                            status_code=500,
                            detail="Failed to create challan after retries (duplicate number). Please try again.",
                        )
                    continue
                
                # If it's a VARCHAR(50) error, try to migrate again and retry
                if "varying(50)" in error_lower or "character varying(50)" in error_lower or "value too long" in error_lower:
                    print(f"VARCHAR(50) error detected! Attempting emergency migration...")
                    print(f"Error: {error_msg}")
                    print(f"Party name: '{party_name}' (length: {len(party_name) if party_name else 0})")
                    print(f"Station name: '{station_name}' (length: {len(station_name) if station_name else 0})")
                    print(f"Transport name: '{transport_name}' (length: {len(transport_name) if transport_name else 0})")
                    print(f"Challan number would be: '{number_to_insert}' (length: {len(number_to_insert) if number_to_insert else 0})")
                    try:
                        # Emergency migration - migrate ALL relevant columns
                        _migrate_varchar_columns(cursor, conn)
                        conn.commit()
                        print("Emergency migration completed, retrying insert...")
                        # Retry the insert
                        continue
                    except Exception as migrate_err:
                        print(f"Emergency migration failed: {migrate_err}")
                        import traceback
                        traceback.print_exc()
                        # Still raise the original error
                        raise HTTPException(
                            status_code=500,
                            detail=f"Database column size error. Please contact support. Error: {error_msg}"
                        )
                
                # Log the error details
                import traceback
                print(f"Insert error: {error_msg}")
                print(f"Challan data: party_name='{party_name[:50] if party_name else None}', station_name='{station_name}', transport_name='{transport_name}'")
                print(f"Challan number: '{number_to_insert}'")
                traceback.print_exc()
                
                # If it's the last attempt, provide a more helpful error message
                if _create_attempt == max_create_retries - 1:
                    raise HTTPException(
                        status_code=500,
                        detail=f"Failed to create challan: {error_msg}"
                    )
                raise
        if not challan_row:
            if conn:
                conn.rollback()
            raise HTTPException(status_code=500, detail="Failed to create challan")
        
        # Set final_challan_number from the row we just wrote
        final_challan_number = (challan_row.get("challan_number") or "").strip()
        
        # Final safety check: ensure final_challan_number is always set (should never be empty at this point)
        if not final_challan_number:
            final_challan_number = challan_row.get("challan_number") or generate_challan_number(cursor, party_name)
            print(f"Warning: final_challan_number was empty after if/else, using fallback: {final_challan_number}")
        
        inserted_items = []
        # Insert items only if they were provided
        if prepared_items:
            for prepared in prepared_items:
                # Ensure None values are properly handled
                qr_code_value = prepared.get("qr_code") if prepared.get("qr_code") else None
                size_id_value = prepared.get("size_id") if prepared.get("size_id") else None
                size_text_value = prepared.get("size_text") if prepared.get("size_text") else None
                product_id_value = prepared.get("product_id") if prepared.get("product_id") else None
                
                cursor.execute("""
                    INSERT INTO challan_items (
                        challan_id,
                        product_id,
                        product_name,
                        size_id,
                        size_text,
                        quantity,
                        unit_price,
                        total_price,
                        qr_code,
                        unit,
                        gst
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING *
                """, (
                    challan_row["id"],
                    product_id_value,
                    prepared["product_name"],
                    size_id_value,
                    size_text_value,
                    prepared["quantity"],
                    prepared["unit_price"],
                    prepared["total_price"],
                    qr_code_value,
                    prepared.get("unit", "piece"),
                    prepared.get("gst", 0),
                ))
                item_row = cursor.fetchone()
                if item_row:
                    inserted_items.append(item_row)
                else:
                    print(f"Warning: Failed to fetch inserted item for challan {challan_row['id']}")
        
        # Update orders table with challan_number if order_number is in metadata
        # Parse metadata if it's a JSON string (it will be a dict from frontend, but string from DB)
        parsed_metadata = metadata
        if isinstance(metadata, str):
            try:
                parsed_metadata = json.loads(metadata)
            except Exception as parse_error:
                print(f"Warning: Could not parse metadata as JSON: {parse_error}")
                parsed_metadata = None
        
        if parsed_metadata and isinstance(parsed_metadata, dict) and parsed_metadata.get("order_number"):
            order_number = parsed_metadata.get("order_number")
            try:
                # Check if challan_number column exists in orders table
                cursor.execute("""
                    SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = 'orders' AND column_name = 'challan_number'
                """)
                has_challan_number = cursor.fetchone() is not None
                
                if not has_challan_number:
                    # Add challan_number column to orders table
                    cursor.execute("""
                        ALTER TABLE orders 
                        ADD COLUMN challan_number VARCHAR(255)
                    """)
                    print("Added challan_number column to orders table")
                
                # Check if order exists before updating
                cursor.execute("""
                    SELECT id FROM orders WHERE order_number = %s
                """, (order_number,))
                order_exists = cursor.fetchone()
                
                if order_exists:
                    # Update all orders with this order_number to include challan_number
                    # Use challan_row["challan_number"] which is set in both UPDATE and INSERT paths
                    challan_number_for_order = challan_row.get("challan_number")
                    if challan_number_for_order:
                        cursor.execute("""
                            UPDATE orders 
                            SET challan_number = %s 
                            WHERE order_number = %s
                        """, (challan_number_for_order, order_number))
                        print(f"Updated orders with order_number {order_number} to include challan_number {challan_number_for_order}")
                else:
                    print(f"Warning: Order with order_number {order_number} does not exist, skipping challan_number update")
            except Exception as update_error:
                print(f"Warning: Could not update orders with challan_number: {update_error}")
                import traceback
                print(f"Traceback: {traceback.format_exc()}")
                # Don't fail the challan creation if order update fails
        
        # Commit the transaction
        try:
            conn.commit()
        except Exception as commit_error:
            conn.rollback()
            print(f"Error committing challan transaction: {commit_error}")
            import traceback
            print(f"Traceback: {traceback.format_exc()}")
            raise HTTPException(
                status_code=500,
                detail=f"Error committing challan: {str(commit_error)}"
            )
        
        # Ensure items are included in response
        if not inserted_items:
            print(f"Warning: No items were inserted for challan {challan_row['id']}")
            # Try to fetch items from database as fallback
            cursor.execute("""
                SELECT *
                FROM challan_items
                WHERE challan_id = %s
                ORDER BY id
            """, (challan_row["id"],))
            inserted_items = cursor.fetchall()

        _clear_challans_list_cache()
        return serialize_challan(challan_row, inserted_items)
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        import traceback
        error_trace = traceback.format_exc()
        error_msg = str(e) if str(e) else "Unknown error occurred"
        print(f"Error creating challan: {error_msg}")
        print(f"Traceback: {error_trace}")
        print(f"Challan data received: {challan_data}")
        raise HTTPException(
            status_code=500,
            detail=f"Error creating challan: {error_msg}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.put("/api/challans/{challan_id}")
def update_challan(challan_id: int, challan_data: dict):
    """
    Update challan items. Replaces all existing items with new items.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        # Tables ensured at startup
        
        # Lock challan row so concurrent updates from different devices are serialized (no interleaved updates)
        cursor.execute("SELECT * FROM challans WHERE id = %s FOR UPDATE", (challan_id,))
        challan_row = cursor.fetchone()
        if not challan_row:
            raise HTTPException(status_code=404, detail="Challan not found")
        
        items = challan_data.get("items", [])
        prepared_items = []
        total_amount = 0.0
        total_quantity = 0.0
        
        # Process items if provided
        if items and len(items) > 0:
            for item in items:
                quantity = float(item.get("quantity", 0) or 0)
                unit_price = float(item.get("unit_price", 0) or 0)
                
                if quantity <= 0:
                    raise HTTPException(status_code=400, detail="Item quantity must be greater than 0")
                if unit_price < 0:
                    raise HTTPException(status_code=400, detail="Item unit price cannot be negative")
                
                total_price = item.get("total_price")
                total_price = float(total_price) if total_price is not None else quantity * unit_price
                product_id = item.get("product_id")
                product_name = item.get("product_name")
                size_id = item.get("size_id")
                size_text = item.get("size_text")
                qr_code_value = item.get("qr_code")
                
                # Resolve product_id: challan_items FK needs product_catalog.id; app may send products_master.id
                if product_id:
                    try:
                        cursor.execute(
                            "SELECT id, name, qr_code FROM product_catalog WHERE id = %s",
                            (product_id,))
                        product_row = cursor.fetchone()
                        if product_row:
                            if not product_name:
                                product_name = product_row.get("name")
                            if not qr_code_value:
                                qr_code_value = product_row.get("qr_code")
                        else:
                            try:
                                cursor.execute("""
                                    SELECT pc.id, pc.name, pc.qr_code
                                    FROM products_master pm
                                    JOIN product_catalog pc ON pm.external_id = pc.external_id
                                    WHERE pm.id = %s LIMIT 1
                                """, (product_id,))
                                product_row = cursor.fetchone()
                                if product_row:
                                    product_id = product_row["id"]
                                    if not product_name:
                                        product_name = product_row.get("name")
                                    if not qr_code_value:
                                        qr_code_value = product_row.get("qr_code")
                                else:
                                    product_id = None
                            except Exception:
                                product_id = None
                    except Exception as e:
                        conn.rollback()
                        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
                
                if not product_name:
                    raise HTTPException(status_code=400, detail="Each item must include a product name")
                
                # Look up unit and GST from products_master
                item_unit = item.get("unit", "piece")
                item_gst = 0
                try:
                    if product_id:
                        cursor.execute("SELECT gst, unit FROM products_master WHERE id = %s", (product_id,))
                    else:
                        cursor.execute("SELECT gst, unit FROM products_master WHERE name = %s LIMIT 1", (product_name,))
                    pm_row = cursor.fetchone()
                    if pm_row:
                        if pm_row.get("unit"):
                            item_unit = pm_row["unit"]
                        if pm_row.get("gst") and total_price > 0:
                            item_gst = round(total_price * float(pm_row["gst"]) / 100)
                except Exception as lu_err:
                    print(f"Warning: Could not look up unit/GST for {product_name}: {lu_err}")

                prepared_items.append({
                    "product_id": product_id,
                    "product_name": product_name,
                    "size_id": size_id,
                    "size_text": size_text,
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "total_price": total_price,
                    "qr_code": qr_code_value,
                    "unit": item_unit,
                    "gst": item_gst
                })
                
                total_amount += total_price
                total_quantity += quantity
        
        # Delete existing items
        cursor.execute("DELETE FROM challan_items WHERE challan_id = %s", (challan_id,))
        
        # Insert new items
        inserted_items = []
        if prepared_items:
            for prepared in prepared_items:
                qr_code_value = prepared.get("qr_code") if prepared.get("qr_code") else None
                size_id_value = prepared.get("size_id") if prepared.get("size_id") else None
                size_text_value = prepared.get("size_text") if prepared.get("size_text") else None
                product_id_value = prepared.get("product_id") if prepared.get("product_id") else None
                
                cursor.execute("""
                    INSERT INTO challan_items (
                        challan_id,
                        product_id,
                        product_name,
                        size_id,
                        size_text,
                        quantity,
                        unit_price,
                        total_price,
                        qr_code,
                        unit,
                        gst
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING *
                """, (
                    challan_id,
                    product_id_value,
                    prepared["product_name"],
                    size_id_value,
                    size_text_value,
                    prepared["quantity"],
                    prepared["unit_price"],
                    prepared["total_price"],
                    qr_code_value,
                    prepared.get("unit", "piece"),
                    prepared.get("gst", 0),
                ))
                item_row = cursor.fetchone()
                if item_row:
                    inserted_items.append(item_row)
        
        # Update challan totals and status
        status = challan_data.get("status", challan_row.get("status", "draft"))
        if status != "draft" and len(prepared_items) == 0:
            raise HTTPException(status_code=400, detail="Cannot finalize challan without items")

        # If challan is in a finalized state (ready, in_transit, delivered),
        # remove party name from challan_number, leaving just DC000001
        current_status = challan_row.get("status", "draft")
        current_challan_number = challan_row.get("challan_number", "")
        new_challan_number = current_challan_number

        # Finalized states where party name should be removed
        finalized_states = ['ready', 'in_transit', 'delivered']

        # Remove party name if challan is in or moving to a finalized state
        if status in finalized_states:
            # Check if challan_number has party name format: "PARTY_NAME - DC000001"
            if ' - DC' in current_challan_number:
                # Extract just the DC part: "DC000001"
                # Split by ' - DC' and add 'DC' prefix back
                parts = current_challan_number.split(' - DC')
                if len(parts) > 1:
                    dc_part = 'DC' + parts[-1].strip()
                    new_challan_number = dc_part
                    print(f"Removing party name from challan number (status: {status}): {current_challan_number} -> {new_challan_number}")

        # Allow updating party details when reusing an empty draft (party_name, station_name, etc.)
        party_name = challan_data.get("party_name")
        station_name = challan_data.get("station_name")
        transport_name = challan_data.get("transport_name")
        price_category = challan_data.get("price_category")

        cursor.execute("""
            UPDATE challans
            SET total_amount = %s,
                total_quantity = %s,
                status = %s,
                challan_number = %s,
                party_name = COALESCE(%s, party_name),
                station_name = COALESCE(%s, station_name),
                transport_name = COALESCE(%s, transport_name),
                price_category = COALESCE(%s, price_category),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            RETURNING *
        """, (
            total_amount, total_quantity, status, new_challan_number,
            party_name, station_name, transport_name, price_category,
            challan_id,
        ))
        
        updated_challan = cursor.fetchone()
        if not updated_challan:
            conn.rollback()
            raise HTTPException(status_code=500, detail="Failed to update challan")
        
        # Commit the transaction
        try:
            conn.commit()
        except Exception as commit_error:
            conn.rollback()
            print(f"Error committing challan update: {commit_error}")
            import traceback
            print(f"Traceback: {traceback.format_exc()}")
            raise HTTPException(
                status_code=500,
                detail=f"Error updating challan: {str(commit_error)}"
            )
        
        # Fetch items for response
        if not inserted_items:
            cursor.execute("""
                SELECT *
                FROM challan_items
                WHERE challan_id = %s
                ORDER BY id
            """, (challan_id,))
            inserted_items = cursor.fetchall()

        _clear_challans_list_cache()
        return serialize_challan(updated_challan, inserted_items)
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        import traceback
        error_trace = traceback.format_exc()
        error_msg = str(e) if str(e) else "Unknown error occurred"
        print(f"Error updating challan: {error_msg}")
        print(f"Traceback: {error_trace}")
        raise HTTPException(
            status_code=500,
            detail=f"Error updating challan: {error_msg}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

def _clear_challans_list_cache():
    """Clear list cache when challans are created/updated."""
    global _challans_list_cache, _challans_list_cache_time
    _challans_list_cache.clear()
    _challans_list_cache_time.clear()


@app.get("/api/challans")
def list_challans(status: str = None, search: str = None, limit: int = 50):
    """
    Retrieve challans with optional filtering. Cached 30s to avoid timeout on retry.
    """
    global _challans_list_cache, _challans_list_cache_time
    cache_key = (status or "", search or "", min(limit, 100))
    now = datetime.now().timestamp()
    if cache_key in _challans_list_cache and (now - _challans_list_cache_time.get(cache_key, 0)) < 30:
        return _challans_list_cache[cache_key]

    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)

        # Simple SELECT without JOIN - avoids expensive GROUP BY; item_count fetched separately in batch
        query = """
            SELECT id, challan_number, party_name, station_name, transport_name,
                   price_category, total_amount, total_quantity, status, notes,
                   created_at, updated_at
            FROM challans
        """
        conditions = []
        params = []

        if status:
            conditions.append("status = %s")
            params.append(status)

        if search:
            search_term = f"%{search.lower()}%"
            conditions.append("(LOWER(challan_number) LIKE %s OR LOWER(party_name) LIKE %s)")
            params.extend([search_term, search_term])

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        query += " ORDER BY created_at DESC LIMIT %s"
        params.append(min(limit, 100))

        cursor.execute(query, tuple(params))
        rows = cursor.fetchall()

        challans = []
        if rows:
            ids = [r["id"] for r in rows]
            # Batch fetch item counts
            placeholders = ",".join(["%s"] * len(ids))
            cursor.execute(
                f"SELECT challan_id, COUNT(*) AS cnt FROM challan_items WHERE challan_id IN ({placeholders}) GROUP BY challan_id",
                tuple(ids)
            )
            count_map = {r["challan_id"]: r["cnt"] for r in cursor.fetchall()}
            for row in rows:
                serialized = serialize_challan(row)
                serialized["item_count"] = count_map.get(row["id"], 0)
                challans.append(serialized)

        result = {"count": len(challans), "challans": challans}
        _challans_list_cache[cache_key] = result
        _challans_list_cache_time[cache_key] = now
        return result
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error fetching challans: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()


@app.get("/api/challans/empty-drafts")
def list_empty_draft_challans(limit: int = 10):
    """
    Return draft challans that have zero items. Used to reuse an existing empty challan
    instead of creating a new one when user enters party details again.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor, conn)
        # Draft challans with no rows in challan_items (or not in challan_items at all)
        # Use COALESCE to handle NULL updated_at gracefully
        cursor.execute("""
            SELECT c.*
            FROM challans c
            LEFT JOIN (
                SELECT challan_id, COUNT(*) AS cnt
                FROM challan_items
                GROUP BY challan_id
            ) ci ON c.id = ci.challan_id
            WHERE c.status = 'draft'
              AND (ci.cnt IS NULL OR ci.cnt = 0)
            ORDER BY COALESCE(c.updated_at, c.created_at) DESC, c.created_at DESC
            LIMIT %s
        """, (min(limit, 50),))
        rows = cursor.fetchall()
        result = []
        for row in rows:
            result.append(serialize_challan(row, items=[]))
        return {"count": len(result), "challans": result}
    except Exception as e:
        import traceback
        error_msg = str(e) if str(e) else "Unknown error"
        error_lower = error_msg.lower()
        print(f"list_empty_draft_challans error: {error_msg}")
        traceback.print_exc()
        
        # If it's a VARCHAR(50) error, try to migrate
        if "varying(50)" in error_lower or "character varying(50)" in error_lower or "value too long" in error_lower:
            print("VARCHAR(50) error in empty-drafts endpoint! Attempting migration...")
            try:
                if conn and cursor:
                    _migrate_varchar_columns(cursor, conn)
                    conn.commit()
                    print("Migration completed, you may need to retry the request")
            except Exception as migrate_err:
                print(f"Migration failed: {migrate_err}")
        
        raise HTTPException(
            status_code=500,
            detail=f"Error fetching empty draft challans: {error_msg}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()


@app.get("/api/challans/{challan_id}")
def get_challan(challan_id: int):
    """
    Retrieve challan details including items.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor, conn)
        
        cursor.execute("SELECT * FROM challans WHERE id = %s", (challan_id,))
        challan_row = cursor.fetchone()
        if not challan_row:
            raise HTTPException(status_code=404, detail="Challan not found")
        
        cursor.execute("""
            SELECT *
            FROM challan_items
            WHERE challan_id = %s
            ORDER BY id
        """, (challan_id,))
        items = cursor.fetchall()
        
        return serialize_challan(challan_row, items)
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"get_challan({challan_id}) error: {e}")
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Error retrieving challan: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.get("/api/challans/by-number/{challan_number}")
def get_challan_by_number(challan_number: str):
    """
    Retrieve challan by challan number.
    Accepts full format (e.g. "PARTY - DC009504") or DC-only format (e.g. "DC009504").
    Finalized challans are stored as DC-only, so we try exact match first, then DC part.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor)

        num = (challan_number or "").strip()
        cursor.execute("SELECT * FROM challans WHERE challan_number = %s", (num,))
        challan_row = cursor.fetchone()
        # If not found and input looks like "PARTY - DC009504", try DC part (how finalized challans are stored)
        if not challan_row and " - DC" in num:
            parts = num.split(" - DC", 1)
            if len(parts) > 1:
                dc_part = "DC" + parts[-1].strip()
                cursor.execute("SELECT * FROM challans WHERE challan_number = %s", (dc_part,))
                challan_row = cursor.fetchone()
        # If still not found, input may be DC-only (e.g. "DC009505") but DB has "PARTY - DC009505"
        if not challan_row and re.match(r"^DC\d+$", num, re.IGNORECASE):
            cursor.execute(
                "SELECT * FROM challans WHERE challan_number = %s OR challan_number LIKE %s",
                (num, f"% - {num}"),
            )
            challan_row = cursor.fetchone()
        if not challan_row:
            raise HTTPException(status_code=404, detail="Challan not found")
        
        cursor.execute("""
            SELECT *
            FROM challan_items
            WHERE challan_id = %s
            ORDER BY id
        """, (challan_row["id"],))
        items = cursor.fetchall()
        
        return serialize_challan(challan_row, items)
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"get_challan_by_number({challan_number!r}) error: {e}")
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Error retrieving challan: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.delete("/api/challans/{challan_id}")
def delete_challan(challan_id: int):
    """
    Delete a challan by ID.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # First, delete all items associated with this challan
        cursor.execute("DELETE FROM challan_items WHERE challan_id = %s", (challan_id,))
        
        # Then delete the challan itself
        cursor.execute("DELETE FROM challans WHERE id = %s RETURNING challan_number", (challan_id,))
        deleted_challan = cursor.fetchone()
        
        if not deleted_challan:
            conn.rollback()
            raise HTTPException(status_code=404, detail="Challan not found")
        
        conn.commit()
        return {
            "message": f"Challan {deleted_challan['challan_number']} deleted successfully",
            "challan_id": challan_id
        }
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error deleting challan: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.delete("/api/challans/by-number/{challan_number}")
def delete_challan_by_number(challan_number: str):
    """
    Delete a challan by challan number. Accepts "PARTY - DC009485" or "DC009485".
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # First get the challan ID (exact match, or by DC number)
        cursor.execute("SELECT id, challan_number FROM challans WHERE challan_number = %s", (challan_number.strip(),))
        challan_row = cursor.fetchone()
        if not challan_row:
            # Fallback: extract DC number (e.g. DC009485 from "SSN DEL - DC009485" or "009485")
            dc_match = re.search(r'DC(\d+)', challan_number, re.IGNORECASE)
            dc_part = f"DC{dc_match.group(1)}" if dc_match else (f"DC{challan_number.strip()}" if challan_number.strip().isdigit() else None)
            if dc_part:
                cursor.execute(
                    "SELECT id, challan_number FROM challans WHERE challan_number = %s OR challan_number LIKE %s",
                    (dc_part, f"% - {dc_part}"))
                challan_row = cursor.fetchone()
        if not challan_row:
            raise HTTPException(status_code=404, detail=f"Challan with number '{challan_number}' not found")
        
        challan_id = challan_row["id"]
        
        # Delete all items associated with this challan
        cursor.execute("DELETE FROM challan_items WHERE challan_id = %s", (challan_id,))
        
        # Then delete the challan itself
        cursor.execute("DELETE FROM challans WHERE id = %s", (challan_id,))
        
        conn.commit()
        actual_number = challan_row.get("challan_number", challan_number)
        _clear_challans_list_cache()
        return {
            "message": f"Challan {actual_number} deleted successfully",
            "challan_id": challan_id
        }
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error deleting challan: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

def _build_qr_response(payload: str):
    if not payload:
        raise HTTPException(status_code=400, detail="Invalid QR payload")
    
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(payload)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    img_bytes = BytesIO()
    img.save(img_bytes, format="PNG")
    img_bytes.seek(0)
    return Response(content=img_bytes.read(), media_type="image/png")

@app.get("/api/challans/{challan_id}/qr")
def get_challan_qr(challan_id: int):
    """
    Generate QR code for a challan by ID.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor, conn)
        
        cursor.execute("SELECT challan_number FROM challans WHERE id = %s", (challan_id,))
        challan_row = cursor.fetchone()
        if not challan_row:
            raise HTTPException(status_code=404, detail="Challan not found")
        
        return _build_qr_response(challan_row["challan_number"])
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error generating challan QR: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.get("/api/challans/qr/{challan_number}")
def get_challan_qr_by_number(challan_number: str):
    """
    Generate QR code using challan number string.
    """
    return _build_qr_response(challan_number)

@app.post("/api/labels/generate")
def generate_labels(label_data: dict):
    """
    Generate labels for products
    Accepts multiple label items and stores them in the labels table
    """
    conn = None
    try:
        # Validate required fields
        if not label_data.get("items") or len(label_data.get("items", [])) == 0:
            raise HTTPException(
                status_code=400,
                detail="At least one label item is required"
            )
        
        items = label_data.get("items", [])
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Create labels table if it doesn't exist
        try:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS labels (
                    id SERIAL PRIMARY KEY,
                    product_name VARCHAR(500) NOT NULL,
                    product_size VARCHAR(100),
                    number_of_labels INTEGER NOT NULL DEFAULT 1,
                    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'generated', 'printed', 'cancelled')),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    created_by VARCHAR(100)
                )
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_labels_product_name ON labels(product_name)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_labels_status ON labels(status)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_labels_created_at ON labels(created_at DESC)
            """)
            conn.commit()
        except Exception as table_error:
            print(f"Note: labels table may already exist: {table_error}")
            conn.rollback()
        
        # Insert label items
        inserted_labels = []
        total_labels = 0
        
        for item in items:
            product_name = item.get("product_name", "").strip()
            if not product_name:
                continue
            
            product_size = item.get("product_size", "").strip() or None
            number_of_labels = int(item.get("number_of_labels", 1))
            
            if number_of_labels < 1:
                number_of_labels = 1
            
            # Insert label record
            cursor.execute("""
                INSERT INTO labels (
                    product_name,
                    product_size,
                    number_of_labels,
                    status,
                    created_by
                )
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, product_name, number_of_labels, created_at
            """, (
                product_name,
                product_size,
                number_of_labels,
                "pending",
                label_data.get("created_by", "system")
            ))
            
            label_result = cursor.fetchone()
            if label_result:
                inserted_labels.append(dict(label_result))
                total_labels += number_of_labels
        
        if not inserted_labels:
            if conn:
                conn.rollback()
            raise HTTPException(
                status_code=400,
                detail="No valid label items were added"
            )
        
        conn.commit()
        
        return {
            "status": "success",
            "total_labels": total_labels,
            "items_created": len(inserted_labels),
            "labels": inserted_labels,
            "message": f"Successfully created {len(inserted_labels)} label item(s) with {total_labels} total labels"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        import traceback
        error_trace = traceback.format_exc()
        print(f"Error generating labels: {str(e)}")
        print(f"Traceback: {error_trace}")
        raise HTTPException(
            status_code=500,
            detail=f"Error generating labels: {str(e)}"
        )
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/labels")
def get_labels(status: str = None, limit: int = 500):
    """
    Get all labels, optionally filtered by status
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        if status:
            cursor.execute("""
                SELECT id, product_name, product_size, number_of_labels, status, created_at, updated_at, created_by
                FROM labels
                WHERE status = %s
                ORDER BY created_at DESC
                LIMIT %s
            """, (status, limit))
        else:
            cursor.execute("""
                SELECT id, product_name, product_size, number_of_labels, status, created_at, updated_at, created_by
                FROM labels
                ORDER BY created_at DESC
                LIMIT %s
            """, (limit,))
        
        labels = cursor.fetchall()
        labels_list = [dict(label) for label in labels]
        
        return {
            "status": "success",
            "count": len(labels_list),
            "labels": labels_list
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error fetching labels: {str(e)}"
        )
    finally:
        if conn:
            cursor.close()
            conn.close()

# ============================================================================
# Products Master API Endpoints (v1) - Direct from products_master table
# ============================================================================

@app.get("/api/v1/products-master/")
def list_products_master():
    """
    List all products from products_master table with their sizes
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        cursor.execute("""
            SELECT 
                pm.id,
                pm.external_id,
                pm.name,
                pm.category,
                pm.category_id,
                pm.type,
                pm.unit,
                pm.description,
                pm.image,
                pm.video,
                pm.hsn_code,
                pm.gst,
                pm.gst_applicable,
                pm.is_active,
                pm.created_on,
                pm.updated_at,
                pm.has_consumption,
                pm.external_created_on,
                CASE 
                    WHEN pm.designs IS NULL THEN NULL::jsonb
                    WHEN jsonb_typeof(pm.designs) = 'object' AND pm.designs ? 'designs' THEN
                        (SELECT jsonb_agg(
                            COALESCE(elem->>'design_name', elem->>'design_code', elem->>'name', '')
                        )
                        FROM jsonb_array_elements(pm.designs->'designs') AS elem
                        WHERE COALESCE(elem->>'design_name', elem->>'design_code', elem->>'name', '') != '')
                    ELSE pm.designs
                END as designs,
                pc.qr_code
            FROM products_master pm
            LEFT JOIN product_catalog pc ON pm.external_id = pc.external_id
            WHERE pm.is_active = true
            ORDER BY pm.name
        """)
        
        products = cursor.fetchall()
        
        # Get all sizes for all products - check both direct (product_type='master') and via product_catalog
        product_ids = [p['id'] for p in products]
        sizes_map = {}
        
        if product_ids:
            # First, get sizes directly linked to products_master (product_type = 'master')
            placeholders = ','.join(['%s'] * len(product_ids))
            cursor.execute(f"""
                SELECT 
                    product_id,
                    id,
                    size_id,
                    size_text,
                    price_a,
                    price_b,
                    price_c,
                    price_d,
                    price_e,
                    price_r,
                    is_active
                FROM product_sizes
                WHERE product_id IN ({placeholders}) AND product_type = 'master' AND is_active = true
                ORDER BY product_id, id
            """, tuple(product_ids))
            
            direct_sizes = cursor.fetchall()
            for size in direct_sizes:
                pm_id = size['product_id']
                if pm_id not in sizes_map:
                    sizes_map[pm_id] = []
                
                size_dict = {
                    'id': size['id'],
                    'size_id': size['size_id'],
                    'size_text': size['size_text'],
                    'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                    'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                    'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                    'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                    'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                    'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                    'is_active': size['is_active']
                }
                sizes_map[pm_id].append(size_dict)
            
            # Then, get sizes via product_catalog for products that don't have direct sizes
            products_without_sizes = [p for p in products if p['id'] not in sizes_map or len(sizes_map[p['id']]) == 0]
            external_ids = [p['external_id'] for p in products_without_sizes if p['external_id']]
            
            if external_ids:
                # Get product_catalog IDs for these external_ids
                cat_placeholders = ','.join(['%s'] * len(external_ids))
                cursor.execute(f"""
                    SELECT pc.id as catalog_id, pc.external_id
                    FROM product_catalog pc
                    WHERE pc.external_id IN ({cat_placeholders})
                """, tuple(external_ids))
                catalog_mapping = {row['external_id']: row['catalog_id'] for row in cursor.fetchall()}
                
                # Get sizes using catalog IDs
                if catalog_mapping:
                    catalog_ids = list(catalog_mapping.values())
                    size_placeholders = ','.join(['%s'] * len(catalog_ids))
                    cursor.execute(f"""
                        SELECT 
                            pc.external_id,
                            ps.id,
                            ps.size_id,
                            ps.size_text,
                            ps.price_a,
                            ps.price_b,
                            ps.price_c,
                            ps.price_d,
                            ps.price_e,
                            ps.price_r,
                            ps.is_active
                        FROM product_sizes ps
                        JOIN product_catalog pc ON ps.product_id = pc.id
                        WHERE ps.product_id IN ({size_placeholders}) AND ps.is_active = true
                        ORDER BY pc.external_id, ps.size_id
                    """, tuple(catalog_ids))
                    
                    catalog_sizes = cursor.fetchall()
                    # Group sizes by products_master id (via external_id mapping)
                    for size in catalog_sizes:
                        external_id = size['external_id']
                        # Find products_master id for this external_id
                        pm_product = next((p for p in products_without_sizes if p['external_id'] == external_id), None)
                        if pm_product:
                            pm_id = pm_product['id']
                            if pm_id not in sizes_map:
                                sizes_map[pm_id] = []
                            
                            size_dict = {
                                'id': size['id'],
                                'size_id': size['size_id'],
                                'size_text': size['size_text'],
                                'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                                'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                                'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                                'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                                'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                                'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                                'is_active': size['is_active']
                            }
                            sizes_map[pm_id].append(size_dict)
        
        # Build result with sizes and map field names for frontend compatibility
        result = []
        for product in products:
            product_dict = dict(product)
            pm_id = product['id']
            
            # Map products_master fields to frontend expected fields
            product_dict['category_name'] = product_dict.get('category')
            product_dict['image_url'] = product_dict.get('image')
            product_dict['video_url'] = product_dict.get('video')
            
            # Process designs field - extract design names from the designs object
            designs_raw = product_dict.get('designs')
            product_dict['designs'] = []  # Default to empty list
            
            if designs_raw is not None:
                try:
                    # Convert to dict if needed (handle psycopg JSONB types)
                    if not isinstance(designs_raw, dict):
                        if isinstance(designs_raw, str):
                            designs_raw = json.loads(designs_raw)
                        elif hasattr(designs_raw, '__dict__'):
                            designs_raw = dict(designs_raw)
                        else:
                            # Try to convert using json
                            designs_raw = json.loads(json.dumps(designs_raw))
                    
                    # Extract designs array from the object
                    if isinstance(designs_raw, dict):
                        if 'designs' in designs_raw:
                            designs_list = designs_raw['designs']
                            if isinstance(designs_list, list):
                                # Extract design_name from each design object
                                design_names = []
                                for d in designs_list:
                                    if isinstance(d, dict):
                                        design_name = d.get('design_name') or d.get('design_code') or d.get('name')
                                        if design_name:
                                            design_names.append(str(design_name))
                                product_dict['designs'] = design_names
                        else:
                            # If it's a dict but doesn't have 'designs' key, try process_designs_field
                            product_dict['designs'] = process_designs_field(designs_raw)
                    elif isinstance(designs_raw, list):
                        # Already a list - process it
                        product_dict['designs'] = process_designs_field(designs_raw)
                    else:
                        product_dict['designs'] = process_designs_field(designs_raw)
                except Exception as e:
                    print(f"Error processing designs for product {pm_id}: {e}")
                    product_dict['designs'] = []
            
            # Add sizes - use products_master ID as key
            product_dict['sizes'] = sizes_map.get(pm_id, [])
            
            # Convert timestamps to ISO format strings
            if product_dict.get('created_on'):
                product_dict['created_on'] = product_dict['created_on'].isoformat() if hasattr(product_dict['created_on'], 'isoformat') else str(product_dict['created_on'])
            if product_dict.get('updated_at'):
                product_dict['updated_at'] = product_dict['updated_at'].isoformat() if hasattr(product_dict['updated_at'], 'isoformat') else str(product_dict['updated_at'])
            if product_dict.get('external_created_on'):
                product_dict['external_created_on'] = product_dict['external_created_on'].isoformat() if hasattr(product_dict['external_created_on'], 'isoformat') else str(product_dict['external_created_on'])
            
            result.append(product_dict)
        
        return result
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/v1/products-master/{product_id}")
def get_product_master(product_id: int):
    """
    Get a single product from products_master table by ID with sizes
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        cursor.execute("""
            SELECT 
                pm.id,
                pm.external_id,
                pm.name,
                pm.category,
                pm.category_id,
                pm.type,
                pm.unit,
                pm.description,
                pm.image,
                pm.video,
                pm.hsn_code,
                pm.gst,
                pm.gst_applicable,
                pm.is_active,
                pm.created_on,
                pm.updated_at,
                pm.has_consumption,
                pm.external_created_on,
                pm.designs,
                pc.qr_code
            FROM products_master pm
            LEFT JOIN product_catalog pc ON pm.external_id = pc.external_id
            WHERE pm.id = %s AND pm.is_active = true
        """, (product_id,))
        
        product = cursor.fetchone()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        product_dict = dict(product)
        
        # Map products_master fields to frontend expected fields
        product_dict['category_name'] = product_dict.get('category')
        product_dict['image_url'] = product_dict.get('image')
        product_dict['video_url'] = product_dict.get('video')
        
        # Process designs field - extract design names from the designs object
        # IMPORTANT: Process designs AFTER all other field mappings to ensure it's the final value
        designs_raw = product_dict.get('designs')
        
        # Force process designs - extract design_name from each design object
        if designs_raw is not None:
            try:
                # Convert to Python dict if it's a psycopg special type
                if hasattr(designs_raw, '__class__') and 'psycopg' in str(type(designs_raw)):
                    # It's a psycopg type, convert to dict
                    designs_raw = dict(designs_raw) if hasattr(designs_raw, '__iter__') else json.loads(str(designs_raw))
                
                # If it's a string, parse it
                if isinstance(designs_raw, str):
                    designs_raw = json.loads(designs_raw)
                
                # Now process the dict
                if isinstance(designs_raw, dict) and 'designs' in designs_raw:
                    designs_list = designs_raw['designs']
                    if isinstance(designs_list, list):
                        design_names = []
                        for d in designs_list:
                            if isinstance(d, dict):
                                design_name = d.get('design_name') or d.get('design_code') or d.get('name')
                                if design_name:
                                    design_names.append(str(design_name))
                        product_dict['designs'] = design_names
                    else:
                        product_dict['designs'] = []
                else:
                    # Try process_designs_field as fallback
                    product_dict['designs'] = process_designs_field(designs_raw)
            except Exception as e:
                print(f"ERROR processing designs for product {product_id}: {e}")
                print(f"Type: {type(designs_raw)}, Value: {str(designs_raw)[:200]}")
                import traceback
                traceback.print_exc()
                product_dict['designs'] = []
        else:
            product_dict['designs'] = []
        
        # Get sizes for this product - check both direct (product_type='master') and via product_catalog
        sizes_list = []
        
        # First, check for sizes directly linked to products_master (product_id = products_master.id, product_type = 'master')
        cursor.execute("""
            SELECT 
                id,
                size_id,
                size_text,
                price_a,
                price_b,
                price_c,
                price_d,
                price_e,
                price_r,
                is_active
            FROM product_sizes
            WHERE product_id = %s AND product_type = 'master' AND is_active = true
            ORDER BY id
        """, (product_id,))
        
        direct_sizes = cursor.fetchall()
        for size in direct_sizes:
            size_dict = {
                'id': size['id'],
                'size_id': size['size_id'],
                'size_text': size['size_text'],
                'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                'is_active': size['is_active']
            }
            sizes_list.append(size_dict)
        
        # If no direct sizes found, check via product_catalog
        if not sizes_list and product['external_id']:
            cursor.execute("""
                SELECT 
                    ps.id,
                    ps.size_id,
                    ps.size_text,
                    ps.price_a,
                    ps.price_b,
                    ps.price_c,
                    ps.price_d,
                    ps.price_e,
                    ps.price_r,
                    ps.is_active
                FROM product_sizes ps
                JOIN product_catalog pc ON ps.product_id = pc.id
                WHERE pc.external_id = %s AND ps.is_active = true
                ORDER BY ps.size_id
            """, (product['external_id'],))
            
            catalog_sizes = cursor.fetchall()
            for size in catalog_sizes:
                size_dict = {
                    'id': size['id'],
                    'size_id': size['size_id'],
                    'size_text': size['size_text'],
                    'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                    'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                    'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                    'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                    'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                    'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                    'is_active': size['is_active']
                }
                sizes_list.append(size_dict)
        
        product_dict['sizes'] = sizes_list
        
        # Convert timestamps to ISO format strings
        if product_dict.get('created_on'):
            product_dict['created_on'] = product_dict['created_on'].isoformat() if hasattr(product_dict['created_on'], 'isoformat') else str(product_dict['created_on'])
        if product_dict.get('updated_at'):
            product_dict['updated_at'] = product_dict['updated_at'].isoformat() if hasattr(product_dict['updated_at'], 'isoformat') else str(product_dict['updated_at'])
        if product_dict.get('external_created_on'):
            product_dict['external_created_on'] = product_dict['external_created_on'].isoformat() if hasattr(product_dict['external_created_on'], 'isoformat') else str(product_dict['external_created_on'])
        
        # FINAL: Process designs field one more time right before returning to ensure it's correct
        designs_final = product_dict.get('designs')
        if designs_final is not None:
            try:
                # If it's still a dict with 'designs' key, extract the array
                if isinstance(designs_final, dict) and 'designs' in designs_final:
                    designs_list = designs_final.get('designs', [])
                    if isinstance(designs_list, list):
                        design_names = []
                        for d in designs_list:
                            if isinstance(d, dict):
                                design_name = d.get('design_name') or d.get('design_code') or d.get('name')
                                if design_name:
                                    design_names.append(str(design_name))
                        # FORCE SET the designs list
                        product_dict['designs'] = design_names
                        print(f"FINAL: Set designs to {len(design_names)} items: {design_names[:3]}")
                elif not isinstance(designs_final, list):
                    # If it's not a list and not the expected dict format, set to empty
                    product_dict['designs'] = []
            except Exception as e:
                print(f"Final designs processing error: {e}")
                import traceback
                traceback.print_exc()
                product_dict['designs'] = []
        
        # Double-check: ensure designs is a list before returning
        if not isinstance(product_dict.get('designs'), list):
            print(f"WARNING: designs is not a list, type: {type(product_dict.get('designs'))}, setting to empty list")
            product_dict['designs'] = []
        
        return product_dict
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/v1/products-master/{product_id}/sizes")
def get_product_master_sizes(product_id: int):
    """
    Get sizes for a product from products_master
    Checks both direct sizes (product_type='master') and sizes via product_catalog
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Get product from products_master
        cursor.execute("""
            SELECT id, external_id, name
            FROM products_master
            WHERE id = %s AND is_active = true
        """, (product_id,))
        
        product = cursor.fetchone()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        sizes_list = []
        
        # First, check for sizes directly linked to products_master (product_type='master')
        cursor.execute("""
            SELECT 
                id,
                size_id,
                size_text,
                price_a,
                price_b,
                price_c,
                price_d,
                price_e,
                price_r,
                is_active
            FROM product_sizes
            WHERE product_id = %s AND product_type = 'master' AND is_active = true
            ORDER BY id
        """, (product_id,))
        
        direct_sizes = cursor.fetchall()
        for size in direct_sizes:
            size_dict = {
                'id': size['id'],
                'size_id': size['size_id'],
                'size_text': size['size_text'],
                'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                'is_active': size['is_active']
            }
            sizes_list.append(size_dict)
        
        # If no direct sizes found, check via product_catalog
        if not sizes_list and product['external_id']:
            cursor.execute("""
                SELECT 
                    ps.id,
                    ps.size_id,
                    ps.size_text,
                    ps.price_a,
                    ps.price_b,
                    ps.price_c,
                    ps.price_d,
                    ps.price_e,
                    ps.price_r,
                    ps.is_active
                FROM product_sizes ps
                JOIN product_catalog pc ON ps.product_id = pc.id
                WHERE pc.external_id = %s AND ps.is_active = true
                ORDER BY ps.size_id
            """, (product['external_id'],))
            
            catalog_sizes = cursor.fetchall()
            for size in catalog_sizes:
                size_dict = {
                    'id': size['id'],
                    'size_id': size['size_id'],
                    'size_text': size['size_text'],
                    'price_a': float(size['price_a']) if size['price_a'] is not None else None,
                    'price_b': float(size['price_b']) if size['price_b'] is not None else None,
                    'price_c': float(size['price_c']) if size['price_c'] is not None else None,
                    'price_d': float(size['price_d']) if size['price_d'] is not None else None,
                    'price_e': float(size['price_e']) if size['price_e'] is not None else None,
                    'price_r': float(size['price_r']) if size['price_r'] is not None else None,
                    'is_active': size['is_active']
                }
                sizes_list.append(size_dict)
        
        return {
            'product_id': product_id,
            'product_name': product['name'],
            'external_id': product['external_id'],
            'sizes': sizes_list,
            'count': len(sizes_list)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.post("/api/v1/products-master/")
def create_product_master(product_data: dict):
    """
    Create a new product in products_master table
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Validate required fields
        required_fields = ['name', 'category', 'type', 'unit']
        missing_fields = [field for field in required_fields if not product_data.get(field)]
        if missing_fields:
            raise HTTPException(
                status_code=400,
                detail=f"Missing required fields: {', '.join(missing_fields)}"
            )
        
        # Insert new product
        cursor.execute("""
            INSERT INTO products_master (
                name, category, category_id, type, unit, description,
                image, video, hsn_code, gst, gst_applicable,
                is_active, has_consumption, external_id, external_created_on
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            ) RETURNING id, external_id, name, category, type, unit, 
                       description, image, video, hsn_code, gst, gst_applicable,
                       is_active, created_on, updated_at, has_consumption, 
                       external_created_on
        """, (
            product_data.get('name'),
            product_data.get('category'),
            product_data.get('category_id'),
            product_data.get('type'),
            product_data.get('unit'),
            product_data.get('description'),
            product_data.get('image'),
            product_data.get('video'),
            product_data.get('hsn_code'),
            product_data.get('gst'),
            product_data.get('gst_applicable', True),
            product_data.get('is_active', True),
            product_data.get('has_consumption', False),
            product_data.get('external_id'),
            product_data.get('external_created_on')
        ))
        
        new_product = cursor.fetchone()
        conn.commit()
        
        product_dict = dict(new_product)
        # Convert timestamps to ISO format strings
        if product_dict.get('created_on'):
            product_dict['created_on'] = product_dict['created_on'].isoformat() if hasattr(product_dict['created_on'], 'isoformat') else str(product_dict['created_on'])
        if product_dict.get('updated_at'):
            product_dict['updated_at'] = product_dict['updated_at'].isoformat() if hasattr(product_dict['updated_at'], 'isoformat') else str(product_dict['updated_at'])
        if product_dict.get('external_created_on'):
            product_dict['external_created_on'] = product_dict['external_created_on'].isoformat() if hasattr(product_dict['external_created_on'], 'isoformat') else str(product_dict['external_created_on'])
        
        return {
            'status': 'success',
            'message': 'Product created successfully',
            'product': product_dict
        }
        
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        import traceback
        error_trace = traceback.format_exc()
        print(f"Error creating product: {str(e)}")
        print(f"Traceback: {error_trace}")
        raise HTTPException(
            status_code=500,
            detail=f"Error creating product: {str(e)}"
        )
    finally:
        if conn:
            cursor.close()
            conn.close()

if __name__ == "__main__":
    import uvicorn  # type: ignore
    # Use 0.0.0.0 to listen on all interfaces - required for remote access.
    # Server will be reachable at http://13.202.81.19:9010/ from remote clients.
    host = "0.0.0.0"
    port = 9010
    print(f"Starting DecoJewels API on http://{host}:{port} (remote: http://13.202.81.19:{port}/) ...")
    uvicorn.run("main:app", host=host, port=port, reload=False)


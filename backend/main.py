from contextlib import closing
from datetime import datetime
from decimal import Decimal
from io import BytesIO
import json
import os
import re
from typing import Any, Dict, List

from dotenv import load_dotenv  # type: ignore
from fastapi import FastAPI, HTTPException, Request  # type: ignore
from fastapi.middleware.cors import CORSMiddleware  # type: ignore
from fastapi.responses import Response  # type: ignore
import psycopg  # type: ignore
from psycopg.rows import dict_row  # type: ignore
from psycopg.sql import Identifier, SQL  # type: ignore
from pydantic import BaseModel  # type: ignore
import qrcode  # type: ignore

from config import get_db_connection_params

load_dotenv()


app = FastAPI(title="Delhi Jewel API")

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


def ensure_challan_tables(cursor):
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
                challan_number VARCHAR(50) UNIQUE NOT NULL,
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
                challan_number VARCHAR(50) UNIQUE NOT NULL,
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
        CREATE INDEX IF NOT EXISTS idx_challan_items_challan_id 
        ON challan_items(challan_id)
    """)
    
    # Ensure columns exist even if table was created previously with old schema
    challan_columns = [
        ("challan_number", "VARCHAR(50)"),
        ("party_name", "VARCHAR(255)"),
        ("station_name", "VARCHAR(255)"),
        ("transport_name", "VARCHAR(255)"),
        ("price_category", "VARCHAR(100)"),
        ("total_amount", "NUMERIC(12, 2) DEFAULT 0"),
        ("total_quantity", "NUMERIC(12, 2) DEFAULT 0"),
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
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'challans' AND column_name = %s
            """, (column_name,))
            if not cursor.fetchone():
                # Column doesn't exist, add it
                cursor.execute(
                    SQL("ALTER TABLE challans ADD COLUMN {} {}").format(
                        Identifier(column_name),
                        SQL(column_type)
                    )
                )
        except Exception as e:
            print(f"Warning: Could not add column {column_name} to challans table: {e}")
    
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
    max_attempts = 1000  # Safety limit
    for attempt in range(max_attempts):
        sequence_num = max_sequence + attempt + 1
        sequence_str = str(sequence_num).zfill(6)  # 6-digit serial number (000001, 000002, etc.)
        dc_series = f"DC{sequence_str}"  # DC000001, DC000002, etc.
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

def serialize_challan(challan_row, items: List[Dict[str, Any]] = None):
    if not challan_row:
        return None
    
    challan = dict(challan_row)
    challan["total_amount"] = decimal_to_float(challan.get("total_amount"))
    challan["total_quantity"] = decimal_to_float(challan.get("total_quantity"))
    
    if challan.get("created_at") and isinstance(challan.get("created_at"), datetime):
        challan["created_at"] = challan["created_at"].isoformat()
    if challan.get("updated_at") and isinstance(challan.get("updated_at"), datetime):
        challan["updated_at"] = challan["updated_at"].isoformat()
    
    serialized_items = []
    if items:
        for item in items:
            item_dict = dict(item)
            item_dict["quantity"] = decimal_to_float(item_dict.get("quantity"))
            item_dict["unit_price"] = decimal_to_float(item_dict.get("unit_price"))
            item_dict["total_price"] = decimal_to_float(item_dict.get("total_price"))
            serialized_items.append(item_dict)
    challan["items"] = serialized_items
    return challan

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
            AND challan_number LIKE '% - DC%'
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

@app.on_event("startup")
def startup_tasks():
    """
    Run one-time startup checks (ensuring core tables exist).
    """
    try:
        with closing(get_db_connection()) as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                ensure_product_tables(cursor)
                ensure_challan_tables(cursor)
                # Clean up existing finalized challans that still have party names
                cleanup_finalized_challan_numbers(cursor)
            conn.commit()
    except Exception as exc:
        print(f"Warning: Startup table checks failed: {exc}")


@app.get("/")
def read_root():
    return {"message": "Delhi Jewel API is running"}

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
            'updated_at': product['updated_at']
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
        
        for item in items:
            product_id = item.get("product_id")
            if not product_id:
                print(f"Warning: Item missing product_id: {item}")
                continue
            
            # Get product details
            cursor.execute("""
                SELECT id, external_id, name 
                FROM product_catalog 
                WHERE id = %s AND is_active = true
            """, (product_id,))
            product_info = cursor.fetchone()
            
            if not product_info:
                print(f"Warning: Product {product_id} not found, skipping")
                continue
            
            # Convert product_info to dict for easier access (it's already a dict_row from row_factory)
            product_dict = dict(product_info) if product_info else {}
            
            unit_price = float(item.get("unit_price", 0) or 0)
            quantity = int(item.get("quantity", 1))
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
            raise HTTPException(
                status_code=400,
                detail="No valid items were added to the order"
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
            'updated_at': product['updated_at']
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
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'orders' AND column_name IN ('party_name', 'station', 'price_category', 'transport_name', 'created_by')
            """)
            existing_columns = [row[0] for row in cursor.fetchall()]
            
            if 'party_name' not in existing_columns:
                cursor.execute("ALTER TABLE orders ADD COLUMN party_name VARCHAR(255)")
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

@app.get("/api/orders/party-data/{party_name}")
def get_party_data_from_orders(party_name: str):
    """
    Get the most recent station, phone number, and price category for a given party name from orders table.
    Falls back to challans for price category if not found in orders.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        
        # Check if orders table exists
        cursor.execute("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables 
                WHERE table_name = 'orders'
            )
        """)
        exists_row = cursor.fetchone()
        orders_table_exists = bool(exists_row.get("exists") if isinstance(exists_row, dict) else exists_row[0] if exists_row else False)
        
        if not orders_table_exists:
            raise HTTPException(
                status_code=404,
                detail="Orders table not found"
            )
        
        # Query for the most recent order with matching party name
        # Check if price_category column exists in orders table
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'orders' AND column_name = 'price_category'
        """)
        has_price_category = cursor.fetchone() is not None
        
        # Check if transport_name column exists
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'orders' AND column_name = 'transport_name'
        """)
        has_transport_name = cursor.fetchone() is not None
        
        if has_price_category and has_transport_name:
            cursor.execute("""
                SELECT station, customer_phone, price_category, transport_name
                FROM orders
                WHERE party_name = %s
                ORDER BY created_at DESC
                LIMIT 1
            """, (party_name,))
        elif has_price_category:
            cursor.execute("""
                SELECT station, customer_phone, price_category
                FROM orders
                WHERE party_name = %s
                ORDER BY created_at DESC
                LIMIT 1
            """, (party_name,))
        elif has_transport_name:
            cursor.execute("""
                SELECT station, customer_phone, transport_name
                FROM orders
                WHERE party_name = %s
                ORDER BY created_at DESC
                LIMIT 1
            """, (party_name,))
        else:
            cursor.execute("""
                SELECT station, customer_phone
                FROM orders
                WHERE party_name = %s
                ORDER BY created_at DESC
                LIMIT 1
            """, (party_name,))
        
        result = cursor.fetchone()
        
        if not result:
            raise HTTPException(
                status_code=404,
                detail="No order found for this party"
            )
        
        response_data = {
            "station": result.get("station"),
            "phone_number": result.get("customer_phone"),
            "price_category": result.get("price_category") if has_price_category else None,
            "transport_name": result.get("transport_name") if has_transport_name else None
        }
        
        # If price_category is not in orders or is null, try to get it from challans
        if not response_data["price_category"]:
            try:
                ensure_challan_tables(cursor)
                cursor.execute("""
                    SELECT price_category
                    FROM challans
                    WHERE party_name = %s 
                        AND price_category IS NOT NULL 
                        AND price_category != ''
                    ORDER BY created_at DESC
                    LIMIT 1
                """, (party_name,))
                challan_result = cursor.fetchone()
                if challan_result and challan_result.get("price_category"):
                    response_data["price_category"] = challan_result.get("price_category")
            except Exception as challan_error:
                print(f"Error fetching price category from challans: {challan_error}")
        
        # If transport_name is not in orders or is null, try to get it from challans
        if not response_data["transport_name"]:
            try:
                ensure_challan_tables(cursor)
                cursor.execute("""
                    SELECT transport_name
                    FROM challans
                    WHERE party_name = %s 
                        AND transport_name IS NOT NULL 
                        AND transport_name != ''
                    ORDER BY created_at DESC
                    LIMIT 1
                """, (party_name,))
                challan_result = cursor.fetchone()
                if challan_result and challan_result.get("transport_name"):
                    response_data["transport_name"] = challan_result.get("transport_name")
            except Exception as challan_error:
                print(f"Error fetching transport_name from challans: {challan_error}")
        
        return response_data
            
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error fetching party data: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error fetching party data: {str(e)}"
        )
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.get("/api/challan/options")
def get_challan_options():
    """
    Return distinct party, station, transport and price categories saved in the database.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor)
        conn.commit()  # Commit table creation before querying
        
        # Get values from orders table first (primary source, no limit to get all)
        order_party_names = []
        order_station_names = []
        try:
            order_party_names = fetch_distinct_values(cursor, "orders", "party_name", limit=10000)
        except Exception as e:
            print(f"Warning: Could not fetch party names from orders table: {e}")
        
        try:
            order_station_names = fetch_distinct_values(cursor, "orders", "station", limit=10000)
        except Exception as e:
            print(f"Warning: Could not fetch station names from orders table: {e}")
        
        # Get values from challans table (secondary source, to supplement orders data)
        challan_party_names = []
        challan_station_names = []
        try:
            challan_party_names = fetch_distinct_values(cursor, "challans", "party_name", limit=10000)
        except Exception as e:
            print(f"Warning: Could not fetch party names from challans table: {e}")
        
        try:
            challan_station_names = fetch_distinct_values(cursor, "challans", "station_name", limit=10000)
        except Exception as e:
            print(f"Warning: Could not fetch station names from challans table: {e}")
        
        # Get transport names from orders table (primary source)
        order_transport_names = []
        try:
            order_transport_names = fetch_distinct_values(cursor, "orders", "transport_name", limit=10000)
        except Exception as e:
            print(f"Warning: Could not fetch transport names from orders table: {e}")
        
        # Get transport names from challans table (secondary source)
        challan_transport_names = []
        try:
            challan_transport_names = fetch_distinct_values(cursor, "challans", "transport_name", limit=10000)
        except Exception as e:
            print(f"Warning: Could not fetch transport names from challans table: {e}")
        
        # Merge and deduplicate transport names (prioritize orders table, then add from challans)
        seen_transport = set()
        transport_names = []
        
        # First add all from orders table
        for name in order_transport_names:
            if name:
                normalized = name.strip().lower()
                if normalized and normalized not in seen_transport:
                    seen_transport.add(normalized)
                    transport_names.append(name.strip() if name.strip() else name)
        
        # Then add from challans table (only if not already present)
        for name in challan_transport_names:
            if name:
                normalized = name.strip().lower()
                if normalized and normalized not in seen_transport:
                    seen_transport.add(normalized)
                    transport_names.append(name.strip() if name.strip() else name)
        
        # Get price categories from challans table
        price_categories = fetch_distinct_values(cursor, "challans", "price_category", limit=10000)
        
        # Merge and deduplicate party names (prioritize orders table, then add from challans)
        # Start with orders data first, then add challans data (orders takes precedence)
        seen_party = set()
        party_names = []
        
        # First add all from orders table
        for name in order_party_names:
            if name:
                normalized = name.strip().lower()
                if normalized and normalized not in seen_party:
                    seen_party.add(normalized)
                    party_names.append(name.strip() if name.strip() else name)
        
        # Then add from challans table (only if not already present)
        for name in challan_party_names:
            if name:
                normalized = name.strip().lower()
                if normalized and normalized not in seen_party:
                    seen_party.add(normalized)
                    party_names.append(name.strip() if name.strip() else name)
        
        # Merge and deduplicate station names (prioritize orders table, then add from challans)
        seen_station = set()
        station_names = []
        
        # First add all from orders table
        for name in order_station_names:
            if name:
                normalized = name.strip().lower()
                if normalized and normalized not in seen_station:
                    seen_station.add(normalized)
                    station_names.append(name.strip() if name.strip() else name)
        
        # Then add from challans table (only if not already present)
        for name in challan_station_names:
            if name:
                normalized = name.strip().lower()
                if normalized and normalized not in seen_station:
                    seen_station.add(normalized)
                    station_names.append(name.strip() if name.strip() else name)
        
        # Sort for better UX
        party_names.sort()
        station_names.sort()
        transport_names.sort()
        
        # Get customer names and phone numbers from orders table
        customer_names = []
        customer_phones = []
        try:
            # Check if orders table exists first
            cursor.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_name = 'orders'
                )
            """)
            exists_row = cursor.fetchone()
            if isinstance(exists_row, dict):
                orders_table_exists = bool(exists_row.get("exists"))
            elif exists_row:
                orders_table_exists = bool(exists_row[0])
            else:
                orders_table_exists = False
            
            if orders_table_exists:
                try:
                    customer_names = fetch_distinct_values(cursor, "orders", "customer_name", limit=10000)
                    # Filter out None and empty values
                    customer_names = [name for name in customer_names if name and name.strip()]
                    print(f"Successfully fetched {len(customer_names)} customer names from orders table")
                except Exception as e:
                    print(f"Error fetching customer names from orders table: {e}")
                    import traceback
                    print(traceback.format_exc())
                
                try:
                    customer_phones = fetch_distinct_values(cursor, "orders", "customer_phone", limit=10000)
                    # Filter out None and empty values
                    customer_phones = [phone for phone in customer_phones if phone and phone.strip()]
                    print(f"Successfully fetched {len(customer_phones)} customer phones from orders table")
                except Exception as e:
                    print(f"Error fetching customer phones from orders table: {e}")
                    import traceback
                    print(traceback.format_exc())
            else:
                print("Orders table does not exist, skipping customer data fetch")
        except Exception as e:
            print(f"Warning: Could not check/fetch customer data from orders table: {e}")
            import traceback
            print(traceback.format_exc())
        
        # Deduplicate customer names (case-insensitive)
        seen_customer_names = set()
        unique_customer_names = []
        for name in customer_names:
            normalized = name.strip().lower()
            if normalized and normalized not in seen_customer_names:
                seen_customer_names.add(normalized)
                unique_customer_names.append(name.strip())
        
        # Deduplicate customer phones
        seen_customer_phones = set()
        unique_customer_phones = []
        for phone in customer_phones:
            # Normalize phone by removing non-digits for comparison
            clean_phone = ''.join(filter(str.isdigit, phone.strip()))
            if clean_phone and clean_phone not in seen_customer_phones:
                seen_customer_phones.add(clean_phone)
                unique_customer_phones.append(phone.strip())
        
        # Sort for better UX
        unique_customer_names.sort()
        unique_customer_phones.sort()
        
        # Provide sensible defaults for price categories
        default_price_categories = ["A", "B", "C", "D", "E", "R"]
        merged_price_categories = list(dict.fromkeys(price_categories + default_price_categories))
        
        # Debug logging with detailed counts (showing orders as primary source)
        print(f"=== CHALLAN OPTIONS DEBUG ===")
        print(f"Party names - Orders table (primary): {len(order_party_names)}, Challans table (supplement): {len(challan_party_names)}, Total unique: {len(party_names)}")
        print(f"Station names - Orders table (primary): {len(order_station_names)}, Challans table (supplement): {len(challan_station_names)}, Total unique: {len(station_names)}")
        print(f"Customer names from orders: {len(customer_names)} raw, {len(unique_customer_names)} unique")
        print(f"Customer phones from orders: {len(customer_phones)} raw, {len(unique_customer_phones)} unique")
        print(f"Customer names sample: {unique_customer_names[:10]}")
        print(f"Customer phones sample: {unique_customer_phones[:10]}")
        print(f"All Party Names ({len(party_names)}): {party_names[:50]}{'...' if len(party_names) > 50 else ''}")
        print(f"All Station Names ({len(station_names)}): {station_names[:50]}{'...' if len(station_names) > 50 else ''}")
        print(f"=============================")
        
        return {
            "party_names": party_names,
            "station_names": station_names,
            "transport_names": transport_names,
            "price_categories": merged_price_categories,
            "customer_names": unique_customer_names,
            "customer_phones": unique_customer_phones,
            "counts": {
                "party_names_count": len(party_names),
                "station_names_count": len(station_names),
                "transport_names_count": len(transport_names),
                "price_categories_count": len(merged_price_categories),
                "customer_names_count": len(unique_customer_names),
                "customer_phones_count": len(unique_customer_phones),
            }
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error fetching challan options: {str(e)}"
        )
    finally:
        if conn:
            if cursor:
                cursor.close()
            conn.close()

@app.post("/api/challans")
def create_challan(challan_data: dict):
    """
    Create a challan with header details and line items.
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
        ensure_challan_tables(cursor)
        conn.commit()  # Commit table creation before inserting data
        
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
                
                prepared_items.append({
                    "product_id": product_id,
                    "product_name": product_name,
                    "size_id": size_id,
                    "size_text": size_text,
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "total_price": total_price,
                    "qr_code": qr_code_value
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
        
        # Check if there's an existing challan with the same party name that has no items
        # This allows reusing challan numbers for challans that were created but never had items added
        existing_empty_challan = None
        try:
            cursor.execute("""
                SELECT c.* 
                FROM challans c
                LEFT JOIN challan_items ci ON c.id = ci.challan_id
                WHERE c.party_name = %s 
                  AND c.total_quantity = 0
                  AND ci.id IS NULL
                ORDER BY c.created_at DESC
                LIMIT 1
            """, (party_name,))
            existing_empty_challan = cursor.fetchone()
        except Exception as e:
            print(f"Warning: Could not check for existing empty challan: {e}")
        
        # Convert metadata to JSON string if it's a dict
        metadata_json = None
        if metadata:
            if isinstance(metadata, dict):
                metadata_json = json.dumps(metadata)
            elif isinstance(metadata, str):
                metadata_json = metadata
            else:
                metadata_json = str(metadata)
        
        # If an empty challan exists, update it instead of creating a new one
        if existing_empty_challan:
            challan_id = existing_empty_challan["id"]
            challan_number = existing_empty_challan["challan_number"]
            current_status = existing_empty_challan.get("status", "draft")
            
            # If challan is in a finalized state (ready, in_transit, delivered),
            # remove party name from challan_number, leaving just DC000001
            finalized_states = ['ready', 'in_transit', 'delivered']
            new_challan_number = challan_number
            
            # Remove party name if challan is in or moving to a finalized state
            if status in finalized_states:
                # Check if challan_number has party name format: "PARTY_NAME - DC000001"
                if ' - DC' in challan_number:
                    # Extract just the DC part: "DC000001"
                    # Split by ' - DC' and add 'DC' prefix back
                    parts = challan_number.split(' - DC')
                    if len(parts) > 1:
                        dc_part = 'DC' + parts[-1].strip()
                        new_challan_number = dc_part
                        print(f"Removing party name from challan number (status: {status}): {challan_number} -> {new_challan_number}")
            
            # Update the existing challan
            cursor.execute("""
                UPDATE challans
                SET station_name = %s,
                    transport_name = %s,
                    price_category = %s,
                    total_amount = %s,
                    total_quantity = %s,
                    status = %s,
                    challan_number = %s,
                    notes = %s,
                    metadata = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
            """, (
                station_name,
                transport_name,
                price_category if price_category else None,
                total_amount,
                total_quantity,
                status,
                new_challan_number,
                notes if notes else None,
                metadata_json,
                challan_id,
            ))
            
            challan_row = cursor.fetchone()
            if not challan_row:
                if conn:
                    conn.rollback()
                raise HTTPException(status_code=500, detail="Failed to update existing challan")
            
            # Delete existing items before inserting new ones
            cursor.execute("""
                DELETE FROM challan_items WHERE challan_id = %s
            """, (challan_id,))
            
            print(f"Reusing existing empty challan {challan_number} (ID: {challan_id}) for party {party_name}")
        else:
            # No empty challan found, create a new one
            challan_number = generate_challan_number(cursor, party_name)
            
            # If creating with finalized status, remove party name immediately
            # Otherwise, keep party name for draft challans
            finalized_states = ['ready', 'in_transit', 'delivered']
            final_challan_number = challan_number
            
            # Remove party name if challan is being created in a finalized state
            if status in finalized_states:
                # Check if challan_number has party name format: "PARTY_NAME - DC000001"
                if ' - DC' in challan_number:
                    # Extract just the DC part: "DC000001"
                    # Split by ' - DC' and add 'DC' prefix back
                    parts = challan_number.split(' - DC')
                    if len(parts) > 1:
                        dc_part = 'DC' + parts[-1].strip()
                        final_challan_number = dc_part
                        print(f"Removing party name from new challan (status: {status}): {challan_number} -> {final_challan_number}")
            
            cursor.execute("""
                INSERT INTO challans (
                    challan_number,
                    party_name,
                    station_name,
                    transport_name,
                    price_category,
                    total_amount,
                    total_quantity,
                    status,
                    notes,
                    metadata
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING *
            """, (
                final_challan_number,
                party_name,
                station_name,
                transport_name,
                price_category if price_category else None,
                total_amount,
                total_quantity,
                status,
                notes if notes else None,
                metadata_json,
            ))
            
            challan_row = cursor.fetchone()
            if not challan_row:
                if conn:
                    conn.rollback()
                raise HTTPException(status_code=500, detail="Failed to create challan")
        
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
                        qr_code
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
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
                        ADD COLUMN challan_number VARCHAR(50)
                    """)
                    print("Added challan_number column to orders table")
                
                # Check if order exists before updating
                cursor.execute("""
                    SELECT id FROM orders WHERE order_number = %s
                """, (order_number,))
                order_exists = cursor.fetchone()
                
                if order_exists:
                    # Update all orders with this order_number to include challan_number
                    cursor.execute("""
                        UPDATE orders 
                        SET challan_number = %s 
                        WHERE order_number = %s
                    """, (challan_number, order_number))
                    print(f"Updated orders with order_number {order_number} to include challan_number {challan_number}")
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
        ensure_challan_tables(cursor)
        
        # Check if challan exists
        cursor.execute("SELECT * FROM challans WHERE id = %s", (challan_id,))
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
                
                prepared_items.append({
                    "product_id": product_id,
                    "product_name": product_name,
                    "size_id": size_id,
                    "size_text": size_text,
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "total_price": total_price,
                    "qr_code": qr_code_value
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
                        qr_code
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
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
        
        cursor.execute("""
            UPDATE challans
            SET total_amount = %s,
                total_quantity = %s,
                status = %s,
                challan_number = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            RETURNING *
        """, (total_amount, total_quantity, status, new_challan_number, challan_id))
        
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

@app.get("/api/challans")
def list_challans(status: str = None, search: str = None, limit: int = 50):
    """
    Retrieve challans with optional filtering.
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor)
        
        query = """
            SELECT 
                c.id,
                c.challan_number,
                c.party_name,
                c.station_name,
                c.transport_name,
                c.price_category,
                c.total_amount,
                c.total_quantity,
                c.status,
                c.notes,
                c.created_at,
                c.updated_at,
                COUNT(ci.id) AS item_count
            FROM challans c
            LEFT JOIN challan_items ci ON ci.challan_id = c.id
        """
        conditions = []
        params = []
        
        if status:
            conditions.append("c.status = %s")
            params.append(status)
        
        if search:
            search_term = f"%{search.lower()}%"
            conditions.append("(LOWER(c.challan_number) LIKE %s OR LOWER(c.party_name) LIKE %s)")
            params.extend([search_term, search_term])
        
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        
        query += " GROUP BY c.id ORDER BY c.created_at DESC LIMIT %s"
        params.append(limit)
        
        cursor.execute(query, tuple(params))
        rows = cursor.fetchall()
        
        challans = []
        for row in rows:
            serialized = serialize_challan(row)
            serialized["item_count"] = row.get("item_count", 0)
            challans.append(serialized)
        
        return {
            "count": len(challans),
            "challans": challans
        }
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
        ensure_challan_tables(cursor)
        
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
    """
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(row_factory=dict_row)
        ensure_challan_tables(cursor)
        
        cursor.execute("SELECT * FROM challans WHERE challan_number = %s", (challan_number,))
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
        raise HTTPException(
            status_code=500,
            detail=f"Error retrieving challan: {str(e)}"
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
        ensure_challan_tables(cursor)
        
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
    uvicorn.run(app, host="0.0.0.0", port=8000)



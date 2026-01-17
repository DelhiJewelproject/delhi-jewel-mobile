"""
Script to create/update the professional orders table
"""
from config import get_db_connection_params
import psycopg

def setup_orders_table():
    try:
        params = get_db_connection_params()
        conn = psycopg.connect(**params)
        cursor = conn.cursor()
        
        # Check if table exists
        cursor.execute("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables 
                WHERE table_name = 'orders'
            )
        """)
        table_exists = cursor.fetchone()[0]
        
        if not table_exists:
            # Create new table
            print("Creating new orders table...")
            cursor.execute("""
                CREATE TABLE orders (
                    id SERIAL PRIMARY KEY,
                    order_number VARCHAR(8) UNIQUE NOT NULL,
                    party_name VARCHAR(255),
                    station VARCHAR(255),
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
                    order_status VARCHAR(50) DEFAULT 'pending',
                    payment_status VARCHAR(50) DEFAULT 'pending',
                    payment_method VARCHAR(50),
                    notes TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    created_by VARCHAR(100)
                )
            """)
        else:
            # Add missing columns
            print("Updating existing orders table...")
            columns_to_add = [
                ("order_number", "VARCHAR(8)"),
                ("party_name", "VARCHAR(255)"),
                ("station", "VARCHAR(255)"),
                ("product_external_id", "INTEGER"),
                ("product_name", "VARCHAR(500)"),
                ("size_id", "INTEGER"),
                ("size_text", "VARCHAR(100)"),
                ("unit_price", "DECIMAL(12, 2)"),
                ("total_price", "DECIMAL(12, 2)"),
                ("customer_email", "VARCHAR(255)"),
                ("customer_address", "TEXT"),
                ("payment_status", "VARCHAR(50) DEFAULT 'pending'"),
                ("payment_method", "VARCHAR(50)"),
                ("notes", "TEXT"),
                ("created_by", "VARCHAR(100)"),
            ]
            
            for col_name, col_type in columns_to_add:
                try:
                    cursor.execute(f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {col_name} {col_type}")
                except Exception as e:
                    print(f"  Column {col_name} might already exist: {e}")
            
            # Rename status to order_status if needed
            cursor.execute("""
                SELECT column_name FROM information_schema.columns 
                WHERE table_name = 'orders' AND column_name = 'status'
            """)
            if cursor.fetchone():
                cursor.execute("""
                    SELECT column_name FROM information_schema.columns 
                    WHERE table_name = 'orders' AND column_name = 'order_status'
                """)
                if not cursor.fetchone():
                    cursor.execute("ALTER TABLE orders RENAME COLUMN status TO order_status")
        
        # Create indexes
        indexes = [
            "CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number)",
            "CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders(product_id)",
            "CREATE INDEX IF NOT EXISTS idx_orders_customer_phone ON orders(customer_phone)",
            "CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(order_status)",
            "CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC)",
            "CREATE INDEX IF NOT EXISTS idx_orders_customer_name ON orders(customer_name)",
        ]
        
        for index_sql in indexes:
            cursor.execute(index_sql)
        
        # Create function to generate 8-digit unique order number
        cursor.execute("""
            CREATE OR REPLACE FUNCTION generate_order_number()
            RETURNS VARCHAR(8) AS $$
            DECLARE
                new_order_number VARCHAR(8);
                is_unique BOOLEAN := FALSE;
                random_num INTEGER;
            BEGIN
                -- Generate 8-digit unique number
                WHILE NOT is_unique LOOP
                    -- Generate random 8-digit number (10000000 to 99999999)
                    random_num := 10000000 + FLOOR(RANDOM() * 90000000)::INTEGER;
                    new_order_number := LPAD(random_num::TEXT, 8, '0');
                    
                    -- Check if it's unique
                    SELECT NOT EXISTS (
                        SELECT 1 FROM orders WHERE order_number = new_order_number
                    ) INTO is_unique;
                END LOOP;
                
                RETURN new_order_number;
            END;
            $$ LANGUAGE plpgsql;
        """)
        
        # Create trigger function
        cursor.execute("""
            CREATE OR REPLACE FUNCTION update_updated_at_column()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW.updated_at = CURRENT_TIMESTAMP;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        """)
        
        # Create trigger
        cursor.execute("DROP TRIGGER IF EXISTS update_orders_updated_at ON orders")
        cursor.execute("""
            CREATE TRIGGER update_orders_updated_at
                BEFORE UPDATE ON orders
                FOR EACH ROW
                EXECUTE FUNCTION update_updated_at_column();
        """)
        
        conn.commit()
        print("Orders table setup completed successfully!")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"Error: {e}")
        if conn:
            conn.rollback()
        raise

if __name__ == "__main__":
    setup_orders_table()


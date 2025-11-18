"""
Database setup script to create tables
Run this once to set up your database tables
"""
import sys
from config import get_db_connection_params
import psycopg2

def setup_database():
    """Create database tables if they don't exist"""
    try:
        params = get_db_connection_params()
        print(f"Connecting to database: {params['host']}/{params['database']}")
        
        conn = psycopg2.connect(**params)
        cursor = conn.cursor()
        
        print("Creating products table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255),
                description TEXT,
                price DECIMAL(10, 2),
                image_url TEXT,
                barcode VARCHAR(255),
                qr_code VARCHAR(255),
                category VARCHAR(100),
                stock INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        print("Creating orders table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id SERIAL PRIMARY KEY,
                product_id INTEGER REFERENCES products(id),
                quantity INTEGER DEFAULT 1,
                customer_name VARCHAR(255),
                customer_phone VARCHAR(20),
                status VARCHAR(50) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        print("Creating indexes...")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_products_qr_code ON products(qr_code)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders(product_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)")
        
        # Check if sample data exists
        cursor.execute("SELECT COUNT(*) FROM products")
        count = cursor.fetchone()[0]
        
        if count == 0:
            print("Inserting sample data...")
            cursor.execute("""
                INSERT INTO products (name, description, price, barcode, category, stock) 
                VALUES
                    ('Gold Ring', 'Beautiful gold ring with diamond', 25000.00, 'GOLD001', 'Rings', 10),
                    ('Silver Necklace', 'Elegant silver necklace', 15000.00, 'SILVER001', 'Necklaces', 5),
                    ('Diamond Earrings', 'Premium diamond earrings', 35000.00, 'DIAMOND001', 'Earrings', 8),
                    ('Platinum Bracelet', 'Luxury platinum bracelet', 45000.00, 'PLATINUM001', 'Bracelets', 3)
            """)
            print(f"Inserted {cursor.rowcount} sample products")
        else:
            print(f"Database already has {count} products, skipping sample data")
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print("\n✅ Database setup completed successfully!")
        print("Tables created: products, orders")
        print("Indexes created for better performance")
        return True
        
    except Exception as e:
        print(f"\n❌ Error setting up database: {e}")
        return False

if __name__ == "__main__":
    print("=" * 50)
    print("Delhi Jewel Database Setup")
    print("=" * 50)
    success = setup_database()
    sys.exit(0 if success else 1)



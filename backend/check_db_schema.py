"""
Check database schema to see what tables and columns exist
"""
from config import get_db_connection_params
import psycopg2

def check_schema():
    try:
        params = get_db_connection_params()
        conn = psycopg2.connect(**params)
        cursor = conn.cursor()
        
        # Check if products table exists
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_type = 'BASE TABLE'
            ORDER BY table_name
        """)
        tables = cursor.fetchall()
        print("Tables in database:")
        for table in tables:
            print(f"  - {table[0]}")
        
        # Check products table columns if it exists
        cursor.execute("""
            SELECT column_name, data_type, character_maximum_length
            FROM information_schema.columns
            WHERE table_name = 'products'
            ORDER BY ordinal_position
        """)
        columns = cursor.fetchall()
        
        if columns:
            print("\nProducts table columns:")
            for col in columns:
                max_len = f"({col[2]})" if col[2] else ""
                print(f"  - {col[0]}: {col[1]}{max_len}")
        else:
            print("\n⚠️ Products table not found!")
        
        # Check orders table columns if it exists
        cursor.execute("""
            SELECT column_name, data_type, character_maximum_length
            FROM information_schema.columns
            WHERE table_name = 'orders'
            ORDER BY ordinal_position
        """)
        columns = cursor.fetchall()
        
        if columns:
            print("\nOrders table columns:")
            for col in columns:
                max_len = f"({col[2]})" if col[2] else ""
                print(f"  - {col[0]}: {col[1]}{max_len}")
        else:
            print("\n⚠️ Orders table not found!")
        
        # Check sample data
        cursor.execute("SELECT COUNT(*) FROM products")
        count = cursor.fetchone()[0]
        print(f"\nTotal products in database: {count}")
        
        if count > 0:
            cursor.execute("SELECT * FROM products LIMIT 3")
            products = cursor.fetchall()
            print("\nSample products:")
            for product in products:
                print(f"  {product}")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_schema()



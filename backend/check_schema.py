from config import get_db_connection_params
import psycopg

params = get_db_connection_params()
conn = psycopg.connect(**params)
cursor = conn.cursor()

print("=== product_catalog columns ===")
cursor.execute("""
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'product_catalog' 
    ORDER BY ordinal_position
""")
for row in cursor.fetchall():
    print(f"  {row[0]}: {row[1]}")

print("\n=== product_sizes columns ===")
cursor.execute("""
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'product_sizes' 
    ORDER BY ordinal_position
""")
for row in cursor.fetchall():
    print(f"  {row[0]}: {row[1]}")

print("\n=== Sample product_catalog data ===")
cursor.execute("SELECT * FROM product_catalog LIMIT 2")
for row in cursor.fetchall():
    print(f"  {row}")

print("\n=== Sample product_sizes data ===")
cursor.execute("SELECT * FROM product_sizes LIMIT 3")
for row in cursor.fetchall():
    print(f"  {row}")

cursor.close()
conn.close()



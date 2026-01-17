"""
Script to fix the foreign key constraint on orders table
Changes product_id foreign key from 'products' to 'product_catalog'
"""
from config import get_db_connection_params
import psycopg

def fix_foreign_key():
    try:
        params = get_db_connection_params()
        conn = psycopg.connect(**params)
        cursor = conn.cursor()
        
        print("Checking foreign key constraints on orders table...")
        
        # Find all foreign key constraints on product_id
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
            WHERE tc.table_name = 'orders'
            AND tc.constraint_type = 'FOREIGN KEY'
            AND kcu.column_name = 'product_id'
        """)
        
        fk_constraints = cursor.fetchall()
        
        if not fk_constraints:
            print("No foreign key constraint found on product_id. Creating one...")
            cursor.execute("""
                ALTER TABLE orders 
                ADD CONSTRAINT orders_product_id_fkey 
                FOREIGN KEY (product_id) 
                REFERENCES product_catalog(id) 
                ON DELETE SET NULL
            """)
            conn.commit()
            print("✅ Created foreign key constraint referencing product_catalog")
        else:
            for constraint in fk_constraints:
                constraint_name = constraint[0]
                foreign_table = constraint[2]
                
                if foreign_table == 'products':
                    print(f"❌ Found incorrect foreign key: {constraint_name} references 'products'")
                    print(f"   Dropping constraint: {constraint_name}")
                    cursor.execute(f"ALTER TABLE orders DROP CONSTRAINT IF EXISTS {constraint_name}")
                    
                    # Check if correct constraint already exists
                    cursor.execute("""
                        SELECT constraint_name
                        FROM information_schema.table_constraints
                        WHERE table_name = 'orders'
                        AND constraint_name = 'orders_product_id_fkey'
                    """)
                    if not cursor.fetchone():
                        print("   Creating correct foreign key constraint...")
                        cursor.execute("""
                            ALTER TABLE orders 
                            ADD CONSTRAINT orders_product_id_fkey 
                            FOREIGN KEY (product_id) 
                            REFERENCES product_catalog(id) 
                            ON DELETE SET NULL
                        """)
                        conn.commit()
                        print("✅ Fixed foreign key constraint to reference product_catalog")
                    else:
                        print("✅ Correct constraint already exists")
                elif foreign_table == 'product_catalog':
                    print(f"✅ Foreign key constraint is correct: {constraint_name} references 'product_catalog'")
                else:
                    print(f"⚠️  Foreign key references unexpected table: {foreign_table}")
        
        cursor.close()
        conn.close()
        print("\n✅ Foreign key fix completed!")
        
    except Exception as e:
        print(f"❌ Error fixing foreign key: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    fix_foreign_key()


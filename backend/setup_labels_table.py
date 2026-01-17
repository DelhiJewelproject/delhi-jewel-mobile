"""
Script to create labels table and add sample data
Run this to set up the labels table in your database
"""
import sys
from config import get_db_connection_params
import psycopg

def setup_labels_table():
    """Create labels table if it doesn't exist and add sample data"""
    try:
        params = get_db_connection_params()
        print(f"Connecting to database: {params['host']}/{params['dbname']}")
        
        conn = psycopg.connect(**params)
        cursor = conn.cursor()
        
        print("Creating labels table...")
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
        
        print("Creating indexes...")
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
        print("✓ Labels table created successfully!")
        
        # Check if table has any data
        cursor.execute("SELECT COUNT(*) FROM labels")
        count = cursor.fetchone()[0]
        print(f"Current labels count: {count}")
        
        # Add sample data if table is empty
        if count == 0:
            print("\nAdding sample data...")
            sample_labels = [
                ("Gold Ring - Classic", "Size 6", 5, "pending", "system"),
                ("Silver Necklace", "Medium", 3, "pending", "system"),
                ("Diamond Earrings", "Small", 2, "generated", "system"),
                ("Pearl Bracelet", "Large", 4, "pending", "system"),
                ("Platinum Ring", "Size 7", 1, "printed", "system"),
            ]
            
            for label in sample_labels:
                cursor.execute("""
                    INSERT INTO labels (product_name, product_size, number_of_labels, status, created_by)
                    VALUES (%s, %s, %s, %s, %s)
                """, label)
            
            conn.commit()
            print(f"✓ Added {len(sample_labels)} sample label records!")
        else:
            print("Table already has data. Skipping sample data insertion.")
        
        # Show all labels
        print("\nCurrent labels in database:")
        cursor.execute("""
            SELECT id, product_name, product_size, number_of_labels, status, created_at
            FROM labels
            ORDER BY created_at DESC
        """)
        labels = cursor.fetchall()
        
        if labels:
            print(f"\n{'ID':<5} {'Product Name':<30} {'Size':<10} {'Qty':<5} {'Status':<12} {'Created At'}")
            print("-" * 90)
            for label in labels:
                print(f"{label[0]:<5} {label[1][:28]:<30} {str(label[2] or ''):<10} {label[3]:<5} {label[4]:<12} {label[5]}")
        else:
            print("No labels found.")
        
        cursor.close()
        conn.close()
        print("\n✓ Setup completed successfully!")
        
    except Exception as e:
        print(f"Error setting up labels table: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    setup_labels_table()


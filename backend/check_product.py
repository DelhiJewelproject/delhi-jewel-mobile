#!/usr/bin/env python3
"""Script to check for a product in the database"""
from config import get_db_connection_params
import psycopg
from psycopg.rows import dict_row
import json

def check_product(product_name):
    """Check if a product exists and return its details"""
    conn = None
    try:
        conn = psycopg.connect(**get_db_connection_params())
        cursor = conn.cursor(row_factory=dict_row)
        
        # Search for products matching the name (case-insensitive, partial match)
        search_pattern = f"%{product_name}%"
        cursor.execute("""
            SELECT 
                id, 
                name, 
                external_id, 
                category, 
                designs, 
                is_active,
                created_on,
                updated_at
            FROM products_master 
            WHERE UPPER(name) LIKE UPPER(%s)
            ORDER BY name
        """, (search_pattern,))
        
        products = cursor.fetchall()
        
        if not products:
            print(f"\n❌ No products found matching '{product_name}'")
            return
        
        print(f"\n✅ Found {len(products)} product(s) matching '{product_name}':\n")
        print("=" * 80)
        
        for product in products:
            print(f"ID: {product['id']}")
            print(f"Name: {product['name']}")
            print(f"External ID: {product['external_id']}")
            print(f"Category: {product['category']}")
            print(f"Active: {product['is_active']}")
            print(f"Designs: {product['designs']}")
            print(f"Created: {product['created_on']}")
            print(f"Updated: {product['updated_at']}")
            
            # Check if product has sizes
            cursor.execute("""
                SELECT COUNT(*) as count
                FROM product_sizes
                WHERE product_id = %s AND product_type = 'master' AND is_active = true
            """, (product['id'],))
            size_count = cursor.fetchone()['count']
            print(f"Sizes (direct): {size_count}")
            
            # Check sizes via product_catalog if external_id exists
            if product['external_id']:
                cursor.execute("""
                    SELECT COUNT(*) as count
                    FROM product_sizes ps
                    JOIN product_catalog pc ON ps.product_id = pc.id
                    WHERE pc.external_id = %s AND ps.is_active = true
                """, (product['external_id'],))
                catalog_size_count = cursor.fetchone()['count']
                print(f"Sizes (via catalog): {catalog_size_count}")
            
            print("-" * 80)
        
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if conn:
            cursor.close()
            conn.close()

if __name__ == "__main__":
    # Check for PEARL T/C
    check_product("PEARL T/C")
    
    # Also check variations
    print("\n" + "=" * 80)
    print("Checking for variations...")
    check_product("PEARL")
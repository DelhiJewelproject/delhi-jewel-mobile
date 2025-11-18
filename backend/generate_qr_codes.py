"""
Script to generate QR codes for all products in product_catalog
QR codes will contain the product's external_id which can be scanned to get product details
"""
from config import get_db_connection_params
import psycopg2
import qrcode
from io import BytesIO
import base64

def generate_qr_code_for_product(external_id: int) -> str:
    """Generate QR code image as base64 string"""
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(str(external_id))
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convert to base64
    buffered = BytesIO()
    img.save(buffered, format="PNG")
    img_str = base64.b64encode(buffered.getvalue()).decode()
    
    return f"data:image/png;base64,{img_str}"

def update_products_with_qr_codes():
    """Update all products in product_catalog with QR codes"""
    try:
        params = get_db_connection_params()
        conn = psycopg2.connect(**params)
        cursor = conn.cursor()
        
        # Check if qr_code column exists, if not add it
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'product_catalog' AND column_name = 'qr_code'
        """)
        
        if not cursor.fetchone():
            print("Adding qr_code column to product_catalog...")
            cursor.execute("""
                ALTER TABLE product_catalog 
                ADD COLUMN qr_code TEXT
            """)
            conn.commit()
            print("Column added successfully")
        
        # Get all active products
        cursor.execute("""
            SELECT id, external_id, name 
            FROM product_catalog 
            WHERE is_active = true
        """)
        
        products = cursor.fetchall()
        print(f"\nFound {len(products)} active products")
        
        updated = 0
        for product_id, external_id, name in products:
            if external_id:
                # Generate QR code data (using external_id as the code)
                qr_data = str(external_id)
                
                # Update the product with QR code
                cursor.execute("""
                    UPDATE product_catalog 
                    SET qr_code = %s 
                    WHERE id = %s
                """, (qr_data, product_id))
                
                updated += 1
                if updated % 10 == 0:
                    print(f"  Updated {updated} products...")
        
        conn.commit()
        print(f"\nSuccessfully updated {updated} products with QR codes")
        
        cursor.close()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"Error: {e}")
        if conn:
            conn.rollback()
        return False

if __name__ == "__main__":
    print("=" * 50)
    print("QR Code Generator for Products")
    print("=" * 50)
    success = update_products_with_qr_codes()
    if success:
        print("\nQR codes generated successfully!")
        print("Products can now be scanned using their external_id")
    else:
        print("\nFailed to generate QR codes")


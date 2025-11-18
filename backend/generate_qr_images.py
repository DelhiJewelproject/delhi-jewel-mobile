"""
Generate QR code images for all products and save them to a folder
This creates physical QR code images that can be printed or displayed for testing
"""
from config import get_db_connection_params
import psycopg2
import qrcode
from PIL import Image, ImageDraw, ImageFont
import os

def generate_qr_code_image(external_id: int, product_name: str, output_dir: str = "qr_codes"):
    """Generate QR code image with product name"""
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate QR code
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_H,  # High error correction
        box_size=15,
        border=4,
    )
    qr.add_data(str(external_id))
    qr.make(fit=True)
    
    # Create QR code image
    qr_img = qr.make_image(fill_color="black", back_color="white")
    
    # Create a larger image with product name
    padding = 40
    img_width = qr_img.width + (padding * 2)
    img_height = qr_img.height + padding + 80  # Extra space for text
    
    # Create new image with white background
    final_img = Image.new('RGB', (img_width, img_height), 'white')
    
    # Paste QR code
    final_img.paste(qr_img, (padding, padding))
    
    # Add product name text
    try:
        draw = ImageDraw.Draw(final_img)
        # Use default font
        font = ImageFont.load_default()
        
        # Truncate product name if too long
        display_name = product_name[:30] + "..." if len(product_name) > 30 else product_name
        
        # Get text size for centering (use textsize for older PIL versions)
        try:
            bbox = draw.textbbox((0, 0), display_name, font=font)
            text_width = bbox[2] - bbox[0]
        except:
            # Fallback for older PIL
            text_width = draw.textlength(display_name, font=font) if hasattr(draw, 'textlength') else len(display_name) * 6
        
        text_x = (img_width - text_width) // 2
        text_y = qr_img.height + padding + 10
        
        # Draw product name
        draw.text((text_x, text_y), display_name, fill='black', font=font)
        
        # Draw external_id
        id_text = f"ID: {external_id}"
        try:
            bbox_id = draw.textbbox((0, 0), id_text, font=font)
            id_width = bbox_id[2] - bbox_id[0]
        except:
            id_width = draw.textlength(id_text, font=font) if hasattr(draw, 'textlength') else len(id_text) * 6
        
        id_x = (img_width - id_width) // 2
        id_y = text_y + 30
        
        draw.text((id_x, id_y), id_text, fill='gray', font=font)
        
    except Exception as e:
        # If text fails, just save QR code without text
        pass
    
    # Save image
    filename = f"{output_dir}/product_{external_id}_{product_name[:20].replace(' ', '_')}.png"
    final_img.save(filename)
    return filename

def generate_all_qr_codes():
    """Generate QR code images for all active products"""
    try:
        params = get_db_connection_params()
        conn = psycopg2.connect(**params)
        cursor = conn.cursor()
        
        # Get all active products
        cursor.execute("""
            SELECT id, external_id, name 
            FROM product_catalog 
            WHERE is_active = true AND external_id IS NOT NULL
            ORDER BY external_id
        """)
        
        products = cursor.fetchall()
        print(f"\nFound {len(products)} active products with external_id")
        print("Generating QR code images...\n")
        
        generated = 0
        for product_id, external_id, name in products:
            try:
                filename = generate_qr_code_image(external_id, name or f"Product {product_id}")
                generated += 1
                print(f"  [{generated}/{len(products)}] Generated: {filename}")
            except Exception as e:
                print(f"  Error generating QR for product {external_id}: {e}")
        
        cursor.close()
        conn.close()
        
        print(f"\n{'='*60}")
        print(f"Successfully generated {generated} QR code images!")
        print(f"QR codes saved in: {os.path.abspath('qr_codes')}")
        print(f"{'='*60}\n")
        
        return True
        
    except Exception as e:
        print(f"Error: {e}")
        if conn:
            conn.rollback()
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("QR Code Image Generator for Products")
    print("=" * 60)
    success = generate_all_qr_codes()
    if success:
        print("QR code images generated successfully!")
        print("You can now print or display these QR codes for testing.")
    else:
        print("Failed to generate QR code images")


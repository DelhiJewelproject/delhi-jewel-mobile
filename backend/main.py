from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import psycopg2
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv
from config import get_database_url

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

# Database connection
def get_db_connection():
    try:
        from config import get_db_connection_params
        params = get_db_connection_params()
        conn = psycopg2.connect(**params)
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        try:
            params = get_db_connection_params()
            print(f"Attempted connection with host: {params.get('host', 'unknown')}")
        except:
            pass
        raise

class ProductResponse(BaseModel):
    id: int = None
    name: str = None
    description: str = None
    price: float = None
    image_url: str = None
    barcode: str = None
    category: str = None
    stock: int = None

@app.get("/")
def read_root():
    return {"message": "Delhi Jewel API is running"}

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
    Retrieve product details by ID with all sizes
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get product from product_catalog
        cursor.execute("""
            SELECT 
                pc.id,
                pc.external_id,
                pc.name,
                pc.category_id,
                pc.category_name,
                pc.image_url,
                pc.video_url,
                pc.qr_code,
                pc.is_active,
                pc.created_at,
                pc.updated_at
            FROM product_catalog pc
            WHERE pc.id = %s AND pc.is_active = true
        """, (product_id,))
        
        product = cursor.fetchone()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        product_dict = dict(product)
        
        # Get sizes for this product
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
            WHERE product_id = %s AND is_active = true
            ORDER BY size_id
        """, (product_id,))
        
        sizes = cursor.fetchall()
        # Convert Decimal to float for JSON serialization
        sizes_list = []
        for size in sizes:
            size_dict = dict(size)
            # Convert Decimal prices to float
            for price_key in ['price_a', 'price_b', 'price_c', 'price_d', 'price_e', 'price_r']:
                if price_key in size_dict and size_dict[price_key] is not None:
                    size_dict[price_key] = float(size_dict[price_key])
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

@app.get("/api/product/barcode/{barcode}")
def get_product_by_barcode(barcode: str):
    """
    Retrieve product details by barcode/QR code
    Searches in external_id and qr_code fields
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Try to find by external_id or qr_code
        cursor.execute("""
            SELECT 
                pc.id,
                pc.external_id,
                pc.name,
                pc.category_id,
                pc.category_name,
                pc.image_url,
                pc.video_url,
                pc.qr_code,
                pc.is_active,
                pc.created_at,
                pc.updated_at
            FROM product_catalog pc
            WHERE (pc.external_id::text = %s OR pc.qr_code = %s) 
            AND pc.is_active = true
            LIMIT 1
        """, (barcode, barcode))
        
        product = cursor.fetchone()
        
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        product_dict = dict(product)
        
        # Get sizes for this product
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
            WHERE product_id = %s AND is_active = true
            ORDER BY size_id
        """, (product['id'],))
        
        sizes = cursor.fetchall()
        # Convert Decimal to float for JSON serialization
        sizes_list = []
        for size in sizes:
            size_dict = dict(size)
            # Convert Decimal prices to float
            for price_key in ['price_a', 'price_b', 'price_c', 'price_d', 'price_e', 'price_r']:
                if price_key in size_dict and size_dict[price_key] is not None:
                    size_dict[price_key] = float(size_dict[price_key])
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
    try:
        import qrcode
        from io import BytesIO
        from fastapi.responses import Response
        
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
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
        
        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(qr_data)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_bytes = BytesIO()
        img.save(img_bytes, format="PNG")
        img_bytes.seek(0)
        
        return Response(content=img_bytes.read(), media_type="image/png")
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generating QR code: {str(e)}")

@app.get("/api/products")
def get_all_products():
    """
    Get all products from product_catalog with their sizes
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get all active products from product_catalog
        cursor.execute("""
            SELECT 
                pc.id,
                pc.external_id,
                pc.name,
                pc.category_id,
                pc.category_name,
                pc.image_url,
                pc.video_url,
                pc.qr_code,
                pc.is_active,
                pc.created_at,
                pc.updated_at
            FROM product_catalog pc
            WHERE pc.is_active = true
            ORDER BY pc.name
            LIMIT 100
        """)
        products = cursor.fetchall()
        
        # Get sizes for each product
        result = []
        for product in products:
            product_dict = dict(product)
            
            # Get sizes for this product
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
                WHERE product_id = %s AND is_active = true
                ORDER BY size_id
            """, (product['id'],))
            
            sizes = cursor.fetchall()
            # Convert Decimal to float for JSON serialization
            sizes_list = []
            for size in sizes:
                size_dict = dict(size)
                # Convert Decimal prices to float
                for price_key in ['price_a', 'price_b', 'price_c', 'price_d', 'price_e', 'price_r']:
                    if price_key in size_dict and size_dict[price_key] is not None:
                        size_dict[price_key] = float(size_dict[price_key])
                sizes_list.append(size_dict)
            product_dict['sizes'] = sizes_list
            
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
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
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
        
        # Calculate total price
        unit_price = order_data.get("unit_price", 0) or 0
        quantity = order_data.get("quantity", 1)
        total_price = float(unit_price) * int(quantity)
        
        # Generate order number
        cursor.execute("SELECT generate_order_number()")
        order_number = cursor.fetchone()[0]
        
        # Insert order into database
        cursor.execute("""
            INSERT INTO orders (
                order_number,
                party_name,
                station,
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
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id, order_number, created_at
        """, (
            order_number,
            order_data.get("party_name"),
            order_data.get("station"),
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
        
        result = cursor.fetchone()
        conn.commit()
        
        return {
            "order_id": result["id"],
            "order_number": result["order_number"],
            "status": "success",
            "created_at": result["created_at"].isoformat() if result["created_at"] else None
        }
        
    except Exception as e:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"Error creating order: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)



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
        db_url = get_database_url()
        conn = psycopg2.connect(db_url)
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
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

@app.get("/api/product/{barcode}", response_model=ProductResponse)
def get_product_by_barcode(barcode: str):
    """
    Retrieve product details by barcode/QR code
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Query to get product by barcode
        # Adjust table and column names based on your actual database schema
        cursor.execute("""
            SELECT * FROM products 
            WHERE barcode = %s OR qr_code = %s
            LIMIT 1
        """, (barcode, barcode))
        
        result = cursor.fetchone()
        
        if result:
            return ProductResponse(**dict(result))
        else:
            raise HTTPException(status_code=404, detail="Product not found")
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.get("/api/products")
def get_all_products():
    """
    Get all products
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute("SELECT * FROM products LIMIT 100")
        results = cursor.fetchall()
        
        return [dict(row) for row in results]
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            cursor.close()
            conn.close()

@app.post("/api/order")
def create_order(order_data: dict):
    """
    Create a new order
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Insert order into database
        # Adjust based on your actual schema
        cursor.execute("""
            INSERT INTO orders (product_id, quantity, customer_name, customer_phone, status)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
        """, (
            order_data.get("product_id"),
            order_data.get("quantity", 1),
            order_data.get("customer_name"),
            order_data.get("customer_phone"),
            "pending"
        ))
        
        order_id = cursor.fetchone()[0]
        conn.commit()
        
        return {"order_id": order_id, "status": "success"}
        
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



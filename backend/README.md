# Delhi Jewel Backend

Python FastAPI backend for Delhi Jewel mobile application.

## Setup

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Update `.env` file with your database credentials

3. Run the server:
```bash
python main.py
```

The API will be available at `http://localhost:8000`

## API Endpoints

- `GET /api/product/{barcode}` - Get product by barcode/QR code
- `GET /api/products` - Get all products
- `POST /api/order` - Create a new order

## Database Schema

Make sure your PostgreSQL database has a `products` table with columns:
- id (integer)
- name (text)
- description (text)
- price (decimal)
- image_url (text)
- barcode (text)
- qr_code (text)
- category (text)
- stock (integer)

And an `orders` table with columns:
- id (integer)
- product_id (integer)
- quantity (integer)
- customer_name (text)
- customer_phone (text)
- status (text)



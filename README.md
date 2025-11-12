# Delhi Jewel Mobile Application

A Flutter mobile application with Python FastAPI backend for Delhi Jewel jewelry business.

## Project Structure

```
Delhi_jewel_mobile/
├── frontend/          # Flutter mobile application
├── backend/          # Python FastAPI backend
└── README.md         # This file
```

## Features

- **Splash Screen**: Professional logo display with elegant design
- **Main Menu**: Four buttons for different functionalities
- **QR/Barcode Scanner**: Scan QR codes to view product details
- **Product Details**: Display product information from database
- **Order Form**: Place orders for products

## Setup Instructions

### Prerequisites

1. **Flutter**: Install Flutter SDK from https://flutter.dev/docs/get-started/install
2. **Python**: Python 3.8 or higher
3. **PostgreSQL**: Database connection (Supabase)

### Backend Setup

1. Navigate to backend directory:
```bash
cd backend
```

2. Create a virtual environment (recommended):
```bash
python -m venv venv
# Windows
venv\Scripts\activate
# Linux/Mac
source venv/bin/activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Update `.env` file with your database credentials (already configured)

5. Run the backend server:
```bash
python main.py
```

The API will be available at `http://localhost:8000`

### Frontend Setup

1. Navigate to frontend directory:
```bash
cd frontend
```

2. Install Flutter dependencies:
```bash
flutter pub get
```

3. Update API URL in `lib/services/api_service.dart`:
   - For Android emulator: `http://10.0.2.2:8000`
   - For iOS simulator: `http://localhost:8000`
   - For physical device: Use your computer's IP address

4. Run the app:
```bash
flutter run
```

## Database Schema

Make sure your PostgreSQL database has the following tables:

### Products Table
```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    description TEXT,
    price DECIMAL(10, 2),
    image_url TEXT,
    barcode VARCHAR(255),
    qr_code VARCHAR(255),
    category VARCHAR(100),
    stock INTEGER
);
```

### Orders Table
```sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER,
    customer_name VARCHAR(255),
    customer_phone VARCHAR(20),
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## API Endpoints

- `GET /api/product/{barcode}` - Get product by barcode/QR code
- `GET /api/products` - Get all products
- `POST /api/order` - Create a new order

## Notes

- The app uses `mobile_scanner` package for QR/barcode scanning
- Make sure to grant camera permissions when running the app
- Update the base URL in `api_service.dart` based on your testing environment

## Troubleshooting

1. **Flutter not found**: Make sure Flutter is installed and added to PATH
2. **Camera not working**: Check that camera permissions are granted in device settings
3. **API connection error**: Verify backend is running and URL is correct
4. **Database connection error**: Check database credentials in `.env` file


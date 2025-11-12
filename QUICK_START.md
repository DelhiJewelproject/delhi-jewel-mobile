# Quick Start Guide - Delhi Jewel App

## Prerequisites Check

Before starting, ensure you have:
- ✅ Python 3.8+ installed
- ✅ Flutter SDK installed (see installation below)
- ✅ PostgreSQL database access (Supabase)

## Step 1: Install Flutter

Run the installation helper:
```powershell
.\install_flutter.ps1
```

Or install manually:
- Download from: https://docs.flutter.dev/get-started/install/windows
- Add Flutter to your PATH
- Run `flutter doctor` to verify

## Step 2: Setup Backend

```powershell
cd backend

# Create virtual environment
python -m venv venv

# Activate (PowerShell)
.\venv\Scripts\Activate.ps1

# Create .env file
.\create_env.ps1

# Install dependencies
pip install -r requirements.txt

# Run server
python main.py
```

Backend will run on: `http://localhost:8000`

## Step 3: Setup Frontend

```powershell
cd frontend

# Install dependencies
flutter pub get

# IMPORTANT: Update API URL in lib/services/api_service.dart
# - Android Emulator: http://10.0.2.2:8000
# - iOS Simulator: http://localhost:8000  
# - Physical Device: http://YOUR_IP:8000

# Run app
flutter run
```

## Step 4: Database Setup

Connect to your Supabase database and run:

```sql
-- Create products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    description TEXT,
    price DECIMAL(10, 2),
    image_url TEXT,
    barcode VARCHAR(255),
    qr_code VARCHAR(255),
    category VARCHAR(100),
    stock INTEGER DEFAULT 0
);

-- Create orders table  
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER DEFAULT 1,
    customer_name VARCHAR(255),
    customer_phone VARCHAR(20),
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO products (name, description, price, barcode, category, stock) VALUES
('Gold Ring', 'Beautiful gold ring', 25000.00, 'GOLD001', 'Rings', 10),
('Silver Necklace', 'Elegant necklace', 15000.00, 'SILVER001', 'Necklaces', 5);
```

## Testing

1. **Backend**: Open browser to `http://localhost:8000` - should see API message
2. **Frontend**: Launch app, should see splash screen with logo
3. **Scanner**: Tap "View" button, grant camera permission, scan a barcode
4. **Order**: Tap "Order Form" button, fill form and submit

## Troubleshooting

- **Flutter not found**: Add Flutter to PATH or reinstall
- **Backend connection error**: Check `.env` file and database credentials
- **Camera not working**: Grant camera permission in device settings
- **API connection failed**: Update API URL in `api_service.dart` for your device type

## Next Steps

- Customize app colors and design
- Add more product images
- Implement additional features
- Build release version for production

For detailed setup, see `SETUP_GUIDE.md`


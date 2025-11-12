# Delhi Jewel - Complete Setup Guide

## Quick Start

### 1. Install Flutter

**Option A: Using Chocolatey (Recommended for Windows)**
```powershell
choco install flutter
```

**Option B: Manual Installation**
1. Download Flutter SDK from: https://docs.flutter.dev/get-started/install/windows
2. Extract to a location (e.g., `C:\src\flutter`)
3. Add Flutter to PATH: Add `C:\src\flutter\bin` to your system PATH
4. Run `flutter doctor` to verify installation

**Option C: Using Git**
```powershell
git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
# Then add C:\src\flutter\bin to PATH
```

### 2. Setup Backend

```powershell
# Navigate to backend directory
cd backend

# Create virtual environment
python -m venv venv

# Activate virtual environment (Windows PowerShell)
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Create .env file with database credentials
# The connection string should be:
# DATABASE_URL=postgresql://postgres.uhmorjigojfxchpmzyxy:Munna2003@@aws-1-ap-south-1.pooler.supabase.com:5432/postgres
# Note: If your password contains @, it will be handled automatically

# Run the backend server
python main.py
```

The backend will run on `http://localhost:8000`

### 3. Setup Frontend

```powershell
# Navigate to frontend directory
cd frontend

# Install Flutter dependencies
flutter pub get

# Update API URL in lib/services/api_service.dart
# For Android emulator: http://10.0.2.2:8000
# For iOS simulator: http://localhost:8000
# For physical device: http://YOUR_COMPUTER_IP:8000

# Run the app
flutter run
```

## Database Setup

Make sure your PostgreSQL database has these tables:

### Create Products Table
```sql
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    description TEXT,
    price DECIMAL(10, 2),
    image_url TEXT,
    barcode VARCHAR(255),
    qr_code VARCHAR(255),
    category VARCHAR(100),
    stock INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Create Orders Table
```sql
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER DEFAULT 1,
    customer_name VARCHAR(255),
    customer_phone VARCHAR(20),
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Insert Sample Data
```sql
INSERT INTO products (name, description, price, barcode, category, stock) VALUES
('Gold Ring', 'Beautiful gold ring with diamond', 25000.00, 'GOLD001', 'Rings', 10),
('Silver Necklace', 'Elegant silver necklace', 15000.00, 'SILVER001', 'Necklaces', 5),
('Diamond Earrings', 'Premium diamond earrings', 50000.00, 'DIAMOND001', 'Earrings', 8);
```

## Testing the Application

### Test Backend API
```powershell
# Test if backend is running
curl http://localhost:8000

# Test product endpoint (replace GOLD001 with actual barcode)
curl http://localhost:8000/api/product/GOLD001
```

### Test Frontend
1. Make sure backend is running
2. Update API URL in `lib/services/api_service.dart` based on your device
3. Run `flutter run` and select your device/emulator
4. Grant camera permissions when prompted
5. Test QR code scanning with a product barcode

## Troubleshooting

### Flutter Issues
- **Flutter not found**: Make sure Flutter is in your PATH
- **Dependencies error**: Run `flutter pub get` again
- **Build errors**: Run `flutter clean` then `flutter pub get`

### Backend Issues
- **Database connection error**: Check `.env` file and database credentials
- **Port already in use**: Change port in `main.py` or kill the process using port 8000
- **Module not found**: Make sure virtual environment is activated and dependencies are installed

### Camera/Scanner Issues
- **Camera not working**: Check app permissions in device settings
- **Scanner not detecting**: Ensure good lighting and steady hand
- **Permission denied**: Grant camera permission manually in device settings

## Project Structure

```
Delhi_jewel_mobile/
├── frontend/                 # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart        # App entry point
│   │   ├── screens/         # All app screens
│   │   ├── models/          # Data models
│   │   └── services/        # API services
│   ├── assets/              # Images and assets
│   └── pubspec.yaml         # Dependencies
├── backend/                 # Python FastAPI backend
│   ├── main.py             # API server
│   ├── config.py           # Database config
│   └── requirements.txt    # Python dependencies
└── README.md               # Main documentation
```

## Next Steps

1. Customize the app design and colors
2. Add more features (inventory management, order history)
3. Implement authentication if needed
4. Add product images to database
5. Deploy backend to a cloud service
6. Build release APK/IPA for production


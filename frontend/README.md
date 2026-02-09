# DecoJewels Flutter Frontend

Flutter mobile application for DecoJewels.

## Setup

1. Make sure Flutter is installed. If not, download from https://flutter.dev/docs/get-started/install

2. Install dependencies:
```bash
flutter pub get
```

3. **Frontend runs locally**; it connects to the remote API at `http://13.202.81.19:9010` by default. To use a local or different backend, run with:
   - Android emulator: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:9010`
   - iOS simulator: `flutter run --dart-define=API_BASE_URL=http://localhost:9010`
   - Physical device: `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:9010` (replace `192.168.x.x` with your PC’s IP, e.g. `192.168.1.100`)

4. Add permissions for camera in:
   - `android/app/src/main/AndroidManifest.xml` - Add camera permissions
   - `ios/Runner/Info.plist` - Add camera usage description

5. Run the app:
```bash
flutter run
```

## When the server (13.202.81.19) is down or unreachable

If you get **"Can't reach this page"** or **ERR_CONNECTION_REFUSED** when the app tries to load options:

1. **Run the backend on your PC**
   - Open a terminal in the backend folder: `d:\delhi-jewel-mobile\backend`
   - Run: `python main.py`  
     (ensure you have a `.env` with database settings; the API will listen on `http://0.0.0.0:9010`)

2. **Find your PC’s IP** (same Wi‑Fi as your phone)
   - In PowerShell: `ipconfig` → look for **IPv4 Address** under your Wi‑Fi adapter (e.g. `192.168.1.100`)

3. **Run the app pointing at your PC**
   - Physical device:  
     `flutter run --dart-define=API_BASE_URL=http://192.168.1.100:9010`  
     (use your actual IP from step 2)
   - Android emulator:  
     `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:9010`

4. **If the app still can’t connect:** allow port 9010 through Windows Firewall, or temporarily turn off the firewall to test.

## Features

- Splash screen with logo
- Main screen with four menu options
- QR/Barcode scanner for product viewing
- Product detail display
- Order form

## Android Permissions

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```

## iOS Permissions

Add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to scan QR codes</string>
```



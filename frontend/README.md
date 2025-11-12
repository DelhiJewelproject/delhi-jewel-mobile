# Delhi Jewel Flutter Frontend

Flutter mobile application for Delhi Jewel.

## Setup

1. Make sure Flutter is installed. If not, download from https://flutter.dev/docs/get-started/install

2. Install dependencies:
```bash
flutter pub get
```

3. Update API URL in `lib/services/api_service.dart`:
   - For Android emulator: Use `http://10.0.2.2:8000`
   - For iOS simulator: Use `http://localhost:8000`
   - For physical device: Use your computer's IP address (e.g., `http://192.168.1.100:8000`)

4. Add permissions for camera in:
   - `android/app/src/main/AndroidManifest.xml` - Add camera permissions
   - `ios/Runner/Info.plist` - Add camera usage description

5. Run the app:
```bash
flutter run
```

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



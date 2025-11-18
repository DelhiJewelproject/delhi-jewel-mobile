# Mobile Testing Guide - Delhi Jewel App

## 📱 How to Connect and Test on Mobile Device

### Prerequisites
1. ✅ Backend is running on `http://localhost:8000`
2. ✅ Your computer and mobile device are on the **same WiFi network**
3. ✅ Flutter is installed and configured

---

## 🔧 Step 1: Find Your Computer's IP Address

**Windows:**
```powershell
ipconfig
```
Look for **IPv4 Address** under your active network adapter (usually `192.168.x.x`)

**Current IP:** `192.168.0.4` (already configured in the app)

---

## 📲 Step 2: Connect Android Device

### Option A: Physical Android Device (Recommended for Camera Testing)

1. **Enable Developer Options:**
   - Go to **Settings** → **About Phone**
   - Tap **Build Number** 7 times
   - You'll see "You are now a developer!"

2. **Enable USB Debugging:**
   - Go to **Settings** → **Developer Options**
   - Enable **USB Debugging**
   - Enable **Install via USB** (if available)

3. **Connect Device:**
   - Connect your Android phone to computer via USB cable
   - On your phone, tap **Allow USB Debugging** when prompted
   - Trust the computer if asked

4. **Verify Connection:**
   ```powershell
   cd f:\delhi-jewel-mobile\frontend
   flutter devices
   ```
   You should see your device listed (e.g., `sdk gphone64 arm64`)

5. **Run the App:**
   ```powershell
   flutter run
   ```
   Or specify device:
   ```powershell
   flutter run -d <device-id>
   ```

### Option B: Android Emulator

1. **Start Android Studio**
2. **Open AVD Manager** (Tools → Device Manager)
3. **Create/Start an Emulator**
4. **Update API URL** in `frontend/lib/services/api_service.dart`:
   ```dart
   static const String baseUrl = 'http://10.0.2.2:8000'; // For emulator
   ```
5. **Run:**
   ```powershell
   flutter run
   ```

---

## 🍎 Step 3: Connect iOS Device (Mac Only)

1. **Connect iPhone via USB**
2. **Trust Computer** on iPhone
3. **Enable Developer Mode:**
   - Settings → Privacy & Security → Developer Mode → ON
4. **Run:**
   ```bash
   flutter run
   ```

---

## 🌐 Step 4: Ensure Backend is Accessible

### Check Backend is Running:
```powershell
# Test from your computer
curl http://localhost:8000/api/health

# Test from mobile device (use your phone's browser)
# Navigate to: http://192.168.0.4:8000/api/health
```

### Firewall Configuration:
If mobile device can't connect, allow port 8000 in Windows Firewall:

1. Open **Windows Defender Firewall**
2. Click **Advanced Settings**
3. Click **Inbound Rules** → **New Rule**
4. Select **Port** → **TCP** → **8000**
5. Allow the connection
6. Apply to all profiles

---

## 🚀 Step 5: Run the App

```powershell
cd f:\delhi-jewel-mobile\frontend
flutter run
```

**First time setup:**
- Flutter will install the app on your device
- Grant camera permission when prompted
- The app will connect to backend automatically

---

## ✅ Testing Checklist

- [ ] Backend is running (`http://localhost:8000/api/health`)
- [ ] Device is connected (`flutter devices` shows your device)
- [ ] Device and computer are on same WiFi
- [ ] Camera permission is granted
- [ ] App launches successfully
- [ ] Can scan QR codes
- [ ] Can view product details
- [ ] Can create orders

---

## 🐛 Troubleshooting

### Device Not Detected:
```powershell
# Check ADB connection
adb devices

# Restart ADB
adb kill-server
adb start-server
```

### Camera Not Working:
- Grant camera permission in device settings
- Check if camera is being used by another app
- Restart the app

### Backend Connection Failed:
1. Verify IP address: `ipconfig`
2. Update `baseUrl` in `frontend/lib/services/api_service.dart`
3. Test backend from phone browser: `http://YOUR_IP:8000/api/health`
4. Check Windows Firewall settings

### Build Errors:
```powershell
flutter clean
flutter pub get
flutter run
```

---

## 📝 Quick Commands Reference

```powershell
# Check connected devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Check Flutter setup
flutter doctor

# Clean and rebuild
flutter clean && flutter pub get && flutter run

# Check backend health
curl http://localhost:8000/api/health
```

---

## 🎯 Current Configuration

- **Backend URL:** `http://192.168.0.4:8000`
- **Backend Port:** `8000`
- **API Base:** `/api`
- **Camera:** Requires runtime permission

---

**Happy Testing! 🎉**



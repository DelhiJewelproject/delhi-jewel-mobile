# Quick Mobile Setup Guide

## 🚨 Current Issue
Your mobile device is not detected because **Android SDK is not installed**.

## ✅ Solution Options

### Option 1: Install Android SDK (Recommended for USB Connection)

1. **Download Android Studio:**
   - Visit: https://developer.android.com/studio
   - Download and install Android Studio
   - During installation, make sure to install:
     - Android SDK
     - Android SDK Platform-Tools
     - Android Emulator

2. **After Installation:**
   ```powershell
   flutter doctor
   ```
   This will verify if Android SDK is now detected.

3. **Enable USB Debugging on Phone:**
   - Settings → About Phone → Tap "Build Number" 7 times
   - Settings → Developer Options → Enable "USB Debugging"
   - Connect phone via USB
   - Accept "Allow USB Debugging" prompt on phone

4. **Check Device:**
   ```powershell
   cd f:\delhi-jewel-mobile\frontend
   flutter devices
   ```

5. **Run on Mobile:**
   ```powershell
   flutter run
   ```
   Select your mobile device from the list.

---

### Option 2: Wireless Debugging (Android 11+, No USB Cable Needed)

1. **On Your Phone:**
   - Settings → Developer Options → Enable "Wireless Debugging"
   - Tap "Wireless Debugging" → "Pair device with pairing code"
   - Note the IP address and port (e.g., `192.168.1.100:12345`)

2. **On Your Computer:**
   ```powershell
   # Install ADB if not available (part of Android SDK Platform-Tools)
   # Or use Flutter's built-in tools
   
   # Connect wirelessly (replace with your phone's IP and port)
   adb connect 192.168.1.100:12345
   ```

3. **Verify:**
   ```powershell
   flutter devices
   ```

4. **Run:**
   ```powershell
   flutter run
   ```

---

### Option 3: Use Flutter Web on Mobile Browser (Quick Test)

Since your backend is already configured for `192.168.0.4:8000`:

1. **Make sure backend is running:**
   ```powershell
   cd f:\delhi-jewel-mobile\backend
   python main.py
   ```

2. **Run Flutter web:**
   ```powershell
   cd f:\delhi-jewel-mobile\frontend
   flutter run -d chrome --web-port=8080
   ```

3. **On your phone's browser:**
   - Open: `http://192.168.0.4:8080`
   - Note: Camera won't work in browser, but you can test other features

---

## 🎯 Recommended: Install Android Studio

**Why?** 
- Full mobile app testing
- Camera access works
- Native performance
- Better debugging

**Quick Install:**
1. Download: https://developer.android.com/studio
2. Install with default settings
3. Open Android Studio once to complete setup
4. Run `flutter doctor` to verify
5. Connect phone and run `flutter devices`

---

## 📱 After Device is Detected

Once `flutter devices` shows your phone:

```powershell
cd f:\delhi-jewel-mobile\frontend
flutter run
```

Select your mobile device from the list (usually option 1 or 2).

---

## ⚡ Quick Commands

```powershell
# Check devices
flutter devices

# Run on mobile (select device when prompted)
flutter run

# Run on specific device
flutter run -d <device-id>

# Check Flutter setup
flutter doctor
```

---

**Need help?** Make sure:
- ✅ Phone is connected via USB (or wireless debugging enabled)
- ✅ USB Debugging is enabled on phone
- ✅ Android SDK is installed (via Android Studio)
- ✅ Phone and computer are on same WiFi (for backend connection)


# Android Studio Installation Guide

## 📥 Download Android Studio

**Official Download Page:** https://developer.android.com/studio

### Quick Steps:

1. **Download:**
   - Visit: https://developer.android.com/studio
   - Click the **"Download Android Studio"** button
   - Accept the terms and conditions
   - The download will start automatically (file size: ~1 GB)

2. **Install:**
   - Run the downloaded `.exe` file (e.g., `android-studio-2024.1.1.12-windows.exe`)
   - Follow the installation wizard:
     - Choose installation location (default is fine)
     - Select components to install:
       - ✅ Android SDK
       - ✅ Android SDK Platform
       - ✅ Android Virtual Device
     - Click "Next" and "Install"
   - Wait for installation to complete (5-10 minutes)

3. **First Launch Setup:**
   - Open Android Studio
   - Choose "Standard" installation type
   - Let it download SDK components (this may take 10-20 minutes)
   - Click "Finish" when done

4. **Verify Installation:**
   ```powershell
   cd f:\delhi-jewel-mobile\frontend
   flutter doctor
   ```
   You should see:
   ```
   [√] Android toolchain - develop for Android devices
   ```

---

## 📱 After Installation - Connect Your Phone

1. **Enable USB Debugging on Phone:**
   - Settings → About Phone
   - Tap "Build Number" 7 times
   - Go back → Settings → Developer Options
   - Enable "USB Debugging"

2. **Connect Phone:**
   - Connect via USB cable
   - Accept "Allow USB Debugging" prompt on phone

3. **Check Device:**
   ```powershell
   flutter devices
   ```
   Your phone should appear in the list!

4. **Run App:**
   ```powershell
   flutter run
   ```
   Select your mobile device from the list.

---

## ⚡ Quick Commands After Installation

```powershell
# Check Flutter setup
flutter doctor

# Check connected devices
flutter devices

# Run on mobile
flutter run
```

---

## 🐛 Troubleshooting

### If Android SDK not detected:
```powershell
# Set Android SDK path manually (if installed to custom location)
flutter config --android-sdk "C:\Users\YourName\AppData\Local\Android\Sdk"
```

### If device still not detected:
1. Make sure USB Debugging is enabled
2. Try different USB cable
3. Install phone drivers (usually auto-installed)
4. Restart ADB:
   ```powershell
   adb kill-server
   adb start-server
   ```

---

**Download Size:** ~1 GB  
**Installation Time:** 10-20 minutes  
**SDK Download:** Additional 2-3 GB (first launch)

**Reference:** [Android Studio Official Site](https://developer.android.com/studio)


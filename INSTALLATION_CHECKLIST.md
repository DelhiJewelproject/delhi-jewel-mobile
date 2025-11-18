# Android Studio Installation Checklist

## ✅ Installation Steps

### Phase 1: Installer Setup (5-10 minutes)
- [ ] Installer window is open
- [ ] Clicked "Next" on welcome screen
- [ ] Selected installation location (default is fine)
- [ ] **VERIFIED these components are checked:**
  - [ ] Android SDK
  - [ ] Android SDK Platform
  - [ ] Android Virtual Device
  - [ ] Performance (Intel HAXM) - if available
- [ ] Clicked "Install"
- [ ] Waited for installation to complete
- [ ] Clicked "Next" and "Finish"

### Phase 2: First Launch Setup (10-20 minutes)
- [ ] Android Studio opened automatically
- [ ] Selected "Standard" installation type
- [ ] Let it download SDK components (this takes time!)
- [ ] Clicked "Finish" when setup completed
- [ ] Android Studio is now open and ready

---

## 🔍 Verification Commands

After installation, run these commands to verify:

```powershell
# Check Flutter setup
cd f:\delhi-jewel-mobile\frontend
flutter doctor

# Check if Android SDK is detected
flutter devices
```

**Expected Result:**
```
[√] Android toolchain - develop for Android devices
```

---

## 📱 Next Steps: Connect Your Phone

1. **Enable USB Debugging:**
   - Settings → About Phone
   - Tap "Build Number" 7 times
   - Settings → Developer Options → Enable "USB Debugging"

2. **Connect Phone:**
   - Connect via USB cable
   - Accept "Allow USB Debugging" prompt

3. **Verify Connection:**
   ```powershell
   flutter devices
   ```
   Your phone should appear in the list!

4. **Run App:**
   ```powershell
   flutter run
   ```

---

## ⚠️ Common Issues

### If Android SDK not detected:
```powershell
# Set Android SDK path manually
flutter config --android-sdk "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk"
```

### If installation stuck:
- Wait a bit longer (SDK download can take 20+ minutes)
- Check internet connection
- Restart Android Studio

---

**Installation File:** `android-studio-2025.2.1.7-windows.exe` (1.37 GB)  
**Installation Location:** `C:\Program Files\Android\Android Studio` (default)  
**SDK Location:** `C:\Users\YourName\AppData\Local\Android\Sdk`


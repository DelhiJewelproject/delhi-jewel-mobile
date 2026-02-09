plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Configure Java toolchain for this project
// Allow Java 17 or higher (including Java 21)
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

android {
    namespace = "com.example.delhi_jewel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.delhi_jewel"
        // minSdk 29 = Android 10 (API level 29) - released October 2019
        // This ensures modern Android features and better security
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Only ARM64 to reduce APK size (most modern devices use ARM64)
        // For POCO C3 and similar devices, ARM64 is sufficient
        // Note: abiFilters removed when using --split-per-abi flag
        // Build with: flutter build apk --release (without --split-per-abi)
        ndk {
            abiFilters += listOf("arm64-v8a")  // Removed armeabi-v7a to reduce size by ~30-40%
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Enable code shrinking and obfuscation to reduce APK size
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // For Play Store: use `flutter build appbundle` for smaller per-device downloads
        }
    }
}

flutter {
    source = "../.."
}

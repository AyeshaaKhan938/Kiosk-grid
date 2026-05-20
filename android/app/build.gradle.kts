plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vmfsusa.kiosk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.vmfsusa.kiosk"
        minSdk = flutter.minSdkVersion   // API 21+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Limit native libs to architectures used by Reyeah vending tablets
        // (most are 32-bit ARM). Building all ABIs roughly triples APK size.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    buildTypes {
        release {
            // Signed with debug keys for testing installs.
            // TODO: replace with production keystore before Play Store / final deploy.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Bundled android-serialport-api native code (replaces the JitPack
    // dependency that was failing to resolve). Source lives in
    // android/app/src/main/cpp — see CMakeLists.txt there.
    //
    // No explicit CMake version pinned so AGP picks whichever ships with
    // the installed NDK (Codemagic has 3.18+ which is sufficient).
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

flutter {
    source = "../.."
}

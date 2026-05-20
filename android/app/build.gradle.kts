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
        minSdk = flutter.minSdkVersion   // API 21+ requerido por usb_serial y Flutter
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with debug keys for testing installs.
            // TODO: replace with production keystore before Play Store / final deploy.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Direct TTY serial access — opens /dev/ttyS* via JNI for talking to the
    // Reyeah Control Board. This is what the factory app uses (confirmed by
    // decompiling). The usb_serial plugin we kept for backward compatibility
    // doesn't see this board because it's wired to the tablet's UART pins,
    // not through a USB-to-serial bridge.
    implementation("com.github.licheedev:Android-SerialPort-API:2.1.1")
}

import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Release signing config ─────────────────────────────────────────────────
// We resolve credentials in this order:
//   1. Codemagic environment variables (CM_KEYSTORE_PATH, CM_KEYSTORE_PASSWORD,
//      CM_KEY_PASSWORD, CM_KEY_ALIAS) — populated automatically when a Code
//      Signing Identity is attached to the build.
//   2. android/key.properties — used for local release builds on your laptop.
//      The file is git-ignored; it must never be committed.
// If neither is available we fall back to the debug keystore so local dev
// `flutter run` still works.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}

val resolvedStoreFile: String? =
    System.getenv("CM_KEYSTORE_PATH") ?: keystoreProperties.getProperty("storeFile")
val resolvedStorePassword: String? =
    System.getenv("CM_KEYSTORE_PASSWORD") ?: keystoreProperties.getProperty("storePassword")
val resolvedKeyPassword: String? =
    System.getenv("CM_KEY_PASSWORD") ?: keystoreProperties.getProperty("keyPassword")
val resolvedKeyAlias: String? =
    System.getenv("CM_KEY_ALIAS") ?: keystoreProperties.getProperty("keyAlias")

val hasReleaseKeystore = listOf(
    resolvedStoreFile, resolvedStorePassword, resolvedKeyPassword, resolvedKeyAlias,
).all { !it.isNullOrBlank() }

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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(resolvedStoreFile!!)
                storePassword = resolvedStorePassword
                keyAlias = resolvedKeyAlias
                keyPassword = resolvedKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Fallback for local development when no keystore is wired up.
                // CI / production builds MUST hit the release config branch.
                println(
                    "[vmfs] No release keystore found — falling back to debug " +
                        "signing. This APK will NOT update existing prod installs."
                )
                signingConfigs.getByName("debug")
            }
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

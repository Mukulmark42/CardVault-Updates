plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.cardvault"

    // Set to 36 as required by modern AndroidX dependencies (androidx.core 1.17.0)
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Fix for ota_update and modern Java features
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.cardvault"
        minSdk = flutter.minSdkVersion // Explicitly set for better Firebase/OTA support
        targetSdk = 35 // targetSdk can stay at 35 while compileSdk is 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Required when adding many dependencies like Firebase/OTA
        multiDexEnabled = true
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FIX: Updated to 2.1.4 as required by ota_update
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Firebase BOM version MUST match firebase_core plugin's FirebaseSDKVersion.
    // firebase_core 2.32.0 → FirebaseSDKVersion=32.8.0
    // Mismatching this (e.g. 34.11.0) breaks the plugin module compilation.
    implementation(platform("com.google.firebase:firebase-bom:32.8.0"))
    implementation("com.google.firebase:firebase-analytics")
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "id.ponpes.ibnuhafidz.absensi"
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
        applicationId = "id.ponpes.ibnuhafidz.absensi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (System.getenv("IBNU_KEYSTORE_PATH") != null) {
            create("privateRelease") {
                storeFile = file(System.getenv("IBNU_KEYSTORE_PATH"))
                storePassword = System.getenv("IBNU_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("IBNU_KEY_ALIAS")
                keyPassword = System.getenv("IBNU_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.findByName("privateRelease") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Publishing must always use an explicitly selected, existing compatible key.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "assembleRelease" || it.name == "bundleRelease" } && System.getenv("IBNU_KEYSTORE_PATH").isNullOrBlank()) {
        throw GradleException("Set IBNU_KEYSTORE_PATH, IBNU_KEYSTORE_PASSWORD, IBNU_KEY_ALIAS and IBNU_KEY_PASSWORD to the existing app signing key before building a release.")
    }
}

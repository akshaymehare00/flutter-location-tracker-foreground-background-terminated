plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val backgroundGeolocation = project(":flutter_background_geolocation")
apply { from("${backgroundGeolocation.projectDir}/background_geolocation.gradle") }

android {
    namespace = "com.example.new_location_tracking"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.new_location_tracking"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = false   // <-- REQUIRED !!!
        }
    }
}

flutter {
    source = "../.."
}

// For Transistor Background Geolocation SDK
// Note: No credentials required for DEBUG builds
repositories {
    maven {
        url = uri("https://dl.bintray.com/transistorsoft/maven")
    }
    maven {
        url = uri("https://androidx.dev/snapshots/builds/6787662/artifacts/repository")
    }
}

import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing (see docs/RELEASING.md), first complete source wins:
// 1. CI: ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD env vars.
// 2. Local: android/key.properties with storeFile, storePassword, keyAlias, keyPassword (git-ignored).
// Otherwise release builds fall back to the debug key so `flutter run --release` keeps working.
data class ReleaseSigning(
    val storeFile: String,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

fun releaseSigningOf(vararg values: String?): ReleaseSigning? =
    if (values.all { !it.isNullOrBlank() }) {
        ReleaseSigning(values[0]!!, values[1]!!, values[2]!!, values[3]!!)
    } else {
        null
    }

val releaseSigning: ReleaseSigning? =
    releaseSigningOf(
        System.getenv("ANDROID_KEYSTORE_PATH"),
        System.getenv("ANDROID_KEYSTORE_PASSWORD"),
        System.getenv("ANDROID_KEY_ALIAS"),
        System.getenv("ANDROID_KEY_PASSWORD"),
    ) ?: rootProject.file("key.properties").takeIf { it.isFile }?.let { keyPropertiesFile ->
        val props = Properties()
        keyPropertiesFile.inputStream().use { props.load(it) }
        releaseSigningOf(
            props.getProperty("storeFile"),
            props.getProperty("storePassword"),
            props.getProperty("keyAlias"),
            props.getProperty("keyPassword"),
        )
    }

android {
    namespace = "com.ava.huskconfig"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ava.huskconfig"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        releaseSigning?.let { signing ->
            create("release") {
                // Relative paths in key.properties resolve against android/app; CI passes an absolute path.
                storeFile = file(signing.storeFile)
                storePassword = signing.storePassword
                keyAlias = signing.keyAlias
                keyPassword = signing.keyPassword
            }
        }
    }

    buildTypes {
        release {
            // Debug-key fallback keeps `flutter run --release` and builds without signing secrets working.
            signingConfig = signingConfigs.getByName(if (releaseSigning != null) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

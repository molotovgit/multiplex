import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Releases are signed with the release key, which lives only on the
// maintainer's PC, outside the repo (see README, "Signing"). Without it
// a release build falls back to the debug key, so anyone can still build.
val signingProps = Properties().apply {
    val path = System.getenv("MULTIPLEX_SIGNING") ?: "${System.getProperty("user.home")}/.multiplex-signing/key.properties"
    val file = File(path)
    if (file.isFile) file.inputStream().use { load(it) }
}
val hasReleaseKey = signingProps.getProperty("storeFile")?.let { File(it).isFile } == true

android {
    namespace = "io.github.molotovgit.multiplex"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.molotovgit.multiplex"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 8.0: adaptive icons, and what the secure storage and
        // fingerprint plugins need.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = File(signingProps.getProperty("storeFile"))
                storePassword = signingProps.getProperty("storePassword")
                keyAlias = signingProps.getProperty("keyAlias")
                keyPassword = signingProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Debug builds install next to the released app ("Multiplex dev"),
        // so testing never replaces it or touches its saved hosts and keys.
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appLabel"] = "Multiplex dev"
        }
        release {
            manifestPlaceholders["appLabel"] = "Multiplex"
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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

dependencies {
    // Pairing: Google's code scanner reads the QR code without the app
    // needing the camera permission.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    // Google's page scanner, for photographing text that a computer then reads.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
}

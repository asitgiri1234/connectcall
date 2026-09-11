import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. key.properties and the keystore are gitignored; on a fresh
// clone without them, release builds fall back to the debug key so the project
// still builds and installs.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

android {
    namespace = "com.asitgiri.connectcall"
    // Pinned above Flutter's default (36) because permission_handler_android
    // compiles against 37. Android SDKs are backward compatible, so compiling
    // against the highest requirement is safe; minSdk still governs which
    // devices can install, and targetSdk still governs runtime behaviour.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.asitgiri.connectcall"
        // Flutter's default is API 24, which clears every dependency floor
        // here: firebase_auth needs 23, Agora and permission_handler need 21.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Keep rules for plugins R8 cannot see being used (see file).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Agora ships optional extension libraries for features this app never
    // uses. Agora documents every one of these as optional: the SDK simply
    // disables the feature when its library is absent. Excluding them saves
    // roughly 29 MB per CPU architecture. Deliberately kept: AI noise
    // suppression and AI echo cancellation (call audio quality) and the video
    // encoder/decoder extensions.
    packaging {
        jniLibs {
            excludes += listOf(
                "**/libagora_lip_sync_extension.so",
                "**/libagora_clear_vision_extension.so",
                "**/libagora_spatial_audio_extension.so",
                "**/libagora_segmentation_extension.so",
                "**/libagora_face_capture_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_audio_beauty_extension.so",
                "**/libagora_content_inspect_extension.so",
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_av1_decoder_extension.so",
                "**/libagora_screen_capture_extension.so",
            )
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

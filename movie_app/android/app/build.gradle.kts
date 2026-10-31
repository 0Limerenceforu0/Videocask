plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.movie_app"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.movie_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 注意：这里不要再写 `ndk { abiFilters += listOf("arm64-v8a") }`。
        // 它既过滤不掉插件（media_kit / sherpa_onnx / libtorrent）自带的 jniLibs，
        // 又会让 `flutter build apk --split-per-abi` 直接报
        // "Conflicting configuration : abiFilters cannot be present when splits abi
        // filters are set"。实测打出的 APK 里三个 ABI 全都在，说明它等于死配置。
        // 按架构分包改用命令行 `--split-per-abi`。
    }

    // 原生崩溃捕获模块：崩溃瞬间把调用栈写入 guanzi_logs/crash_*.txt（手机端直接提取）。
    // 不设置 ndk.abiFilters（会与 --split-per-abi 冲突），cmake 按目标 ABI 各自构建。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

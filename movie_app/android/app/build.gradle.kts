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

// ── 编译前剔除 integration_test 的插件注册 ──────────────────────────────
//
// `integration_test` 在 dev_dependencies 里，Flutter 每次构建都会把它写进自动
// 生成的 GeneratedPluginRegistrant.java；但 release 变体里没有该包的 Java 类，
// `compileReleaseJavaWithJavac` 会直接报：
//   程序包 dev.flutter.plugins.integration_test 不存在
// 这个文件是纯生成物（已被 android/.gitignore 忽略），在 Java 编译前删掉相关行即可；
// debug / 集成测试仍保留注册，不受影响。
// 之前靠「构建前手工删文件」，但 Flutter 在构建过程中会重新生成，删了没用。
val generatedRegistrant = layout.projectDirectory
    .file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    .asFile

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("JavaWithJavac") }
    .configureEach {
        doFirst {
            if (generatedRegistrant.exists()) {
                val kept = generatedRegistrant.readLines()
                    .filterNot { it.contains("integration_test") }
                generatedRegistrant.writeText(kept.joinToString("\n"))
            }
        }
    }

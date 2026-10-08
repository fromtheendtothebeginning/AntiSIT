plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "top.anticraft.campus_service"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // GitHub 发布签名：release.keystore 随仓库公开。公开仓库的 CI 拿不到机密，而密钥每次
    // 随机生成会让用户无法覆盖安装升级，所以固定一把专用密钥。密码与密钥同处仓库，它不构成
    // 安全边界，只保证各版本签名一致、可互相覆盖安装；debug 构建仍用本机 debug 密钥。
    signingConfigs {
        create("release") {
            storeFile = file("release.keystore")
            storePassword = "antisit"
            keyAlias = "antisit"
            keyPassword = "antisit"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications 的定时通知用到 java.time；minSdk 24 上必须开脱糖（core library desugaring）
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "top.anticraft.campus_service"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

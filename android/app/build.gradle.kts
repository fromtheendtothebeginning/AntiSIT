import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名只从 `android/key.properties`（不进仓库）或环境变量读取，仓库里不再内置任何
// 签名私钥。本地 release 构建前先按 README「发布签名」配置；CI 从 GitHub Secrets 写入。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

fun signingValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key)?.takeIf { it.isNotBlank() }
        ?: System.getenv(env)?.takeIf { it.isNotBlank() }

// 只有 release 构建才强制要求签名配置：debug 构建 / IDE 同步没有私钥也能跑。
val buildingRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (buildingRelease && signingValue("storeFile", "RELEASE_STORE_FILE") == null) {
    error(
        "缺少发布签名配置：请在 android/key.properties 或环境变量中提供 " +
            "storeFile / storePassword / keyAlias / keyPassword（见 README「发布签名」）"
    )
}

android {
    namespace = "top.anticraft.campus_service"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            signingValue("storeFile", "RELEASE_STORE_FILE")?.let { storeFile = file(it) }
            signingValue("storePassword", "RELEASE_STORE_PASSWORD")?.let { storePassword = it }
            signingValue("keyAlias", "RELEASE_KEY_ALIAS")?.let { keyAlias = it }
            signingValue("keyPassword", "RELEASE_KEY_PASSWORD")?.let { keyPassword = it }
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
    // 应用内更新：MainActivity 用 FileProvider 把下载好的 APK 只读共享给系统安装器
    implementation("androidx.core:core:1.13.1")
}

flutter {
    source = "../.."
}

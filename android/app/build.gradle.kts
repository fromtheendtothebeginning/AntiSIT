import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：优先 `android/key.properties`（不进仓库），其次环境变量，最后才回落到仓库内的
// release.keystore。仓库里的那把密钥是为了让历史版本能互相覆盖安装而公开的，**不构成安全边界**：
// 拿到仓库的人都能签出可覆盖安装的包。轮换步骤见 README「发布签名」。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

fun signingValue(key: String, env: String, fallback: String): String =
    (keystoreProperties.getProperty(key)?.takeIf { it.isNotBlank() })
        ?: System.getenv(env)?.takeIf { it.isNotBlank() }
        ?: fallback

android {
    namespace = "top.anticraft.campus_service"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            storeFile = file(signingValue("storeFile", "RELEASE_STORE_FILE", "release.keystore"))
            storePassword = signingValue("storePassword", "RELEASE_STORE_PASSWORD", "antisit")
            keyAlias = signingValue("keyAlias", "RELEASE_KEY_ALIAS", "antisit")
            keyPassword = signingValue("keyPassword", "RELEASE_KEY_PASSWORD", "antisit")
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

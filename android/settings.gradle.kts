pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // 依赖仓库：本机（国内）先用阿里云镜像加速；CI 的 runner 在境外，
    // 走镜像常超时 / 被拒，flutter 那边只会看到一句
    // "Gradle threw an error while downloading artifacts from the network"，
    // 所以 CI 上跳过镜像、直连官方源。
    val onCi = !System.getenv("CI").isNullOrEmpty()
    repositories {
        if (!onCi) {
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/public")
            maven("https://maven.aliyun.com/repository/gradle-plugin")
        }
        google()
        mavenCentral()
        gradlePluginPortal()
        // CI 上官方源也会抽风：2026-11-28 dev.12 那次 Maven Central 直接回
        // 429 Too Many Requests，Gradle 三次重试全挂在解析 kotlin-gradle-plugin 上。
        // Gradle 是按仓库顺序逐个试的，所以把阿里云放最后当兜底——官方源正常时
        // 根本不会走到它，真被限流时还能用镜像取到同一份构件。
        if (onCi) {
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/public")
            maven("https://maven.aliyun.com/repository/gradle-plugin")
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")

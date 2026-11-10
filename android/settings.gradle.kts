pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Subidas el 2026-11-10 porque el build de Android se CAYÓ, no por gusto:
// androidx.core 1.17 y androidx.browser 1.9, que entraron solas al resolver
// las dependencias con Flutter 3.44, exigen AGP 8.9.1 o más. AGP 8.13 pide a
// su vez Gradle 8.13+ (acá, 8.14.6) y con él se van también los avisos de
// Kotlin que Flutter venía dando.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.21" apply false
}

include(":app")

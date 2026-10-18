import java.net.URI
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
val signingValues = listOf("RC_KEYSTORE_PATH", "RC_KEYSTORE_PASSWORD", "RC_KEY_ALIAS", "RC_KEY_PASSWORD").associateWith { System.getenv(it) }
if (releaseRequested) {
    if (signingValues.values.any { it.isNullOrBlank() }) throw GradleException("Release signing requires RC_KEYSTORE_PATH, RC_KEYSTORE_PASSWORD, RC_KEY_ALIAS and RC_KEY_PASSWORD.")
    if (!file(signingValues["RC_KEYSTORE_PATH"]!!).isFile) throw GradleException("Release keystore is missing.")
    val defines = (project.findProperty("dart-defines") as? String ?: "").split(",").filter { it.isNotEmpty() }.map { String(Base64.getDecoder().decode(it)) }
    val api = defines.find { it.startsWith("API_URL=") }?.substringAfter("=")
    val uri = api?.let { URI(it) }
    if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null || uri.query != null || uri.fragment != null || uri.path != "/v1") throw GradleException("Release requires --dart-define=API_URL=https://YOUR_API_HOST/v1")
}

android {
    namespace = "in.ruralconnect.ruralconnect_bus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.ruralconnect.ruralconnect_bus"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
        if (releaseRequested) {
            create("production") {
                storeFile = file(signingValues["RC_KEYSTORE_PATH"]!!)
                storePassword = signingValues["RC_KEYSTORE_PASSWORD"]
                keyAlias = signingValues["RC_KEY_ALIAS"]
                keyPassword = signingValues["RC_KEY_PASSWORD"]
            }
        }
    }
    buildTypes {
        release {
            if (releaseRequested) signingConfig = signingConfigs.getByName("production")
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


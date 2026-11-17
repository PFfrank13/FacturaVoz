import java.util.Properties
import java.io.File
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val facturavozSigningProperties = Properties()
val facturavozSigningFile = File(
    System.getProperty("user.home"),
    "FacturaVoz-Signing/signing.properties"
)

// Debug CI does not require a private distribution keystore. Release always
// requires the real signing file; never use a debug key for production output.
val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (facturavozSigningFile.isFile) {
    facturavozSigningFile.inputStream().use {
        facturavozSigningProperties.load(it)
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = facturavozSigningFile.isFile &&
    releaseSigningKeys.all { !facturavozSigningProperties.getProperty(it).isNullOrBlank() }
// Release keys must exist outside source control, not just be non-empty strings.
// A debug keystore or a copied key inside the repository is never distributable.
val releaseKeystore = if (hasReleaseSigning) {
    val setting = File(facturavozSigningProperties.getProperty("storeFile"))
    (if (setting.isAbsolute) setting else File(project.projectDir, setting.path)).canonicalFile
} else null
val sourceRepository = File(project.projectDir, "../../..").canonicalFile.toPath()
val hasSafeReleaseSigning = hasReleaseSigning &&
    releaseKeystore?.isFile == true &&
    !releaseKeystore.toPath().startsWith(sourceRepository) &&
    !releaseKeystore.name.equals("debug.keystore", ignoreCase = true) &&
    !facturavozSigningProperties.getProperty("keyAlias").equals("androiddebugkey", ignoreCase = true)
check(!isReleaseTask || hasSafeReleaseSigning) {
    "Firma release bloqueada: configura ~/FacturaVoz-Signing/signing.properties " +
        "con un keystore real FUERA del repositorio (nunca debug.keystore)."
}
android {
    namespace = "pe.tuempresa.facturavoz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.solvexsoftware.facturavoz"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasSafeReleaseSigning) {
            create("release") {
                storeFile = releaseKeystore!!
                storePassword = facturavozSigningProperties.getProperty("storePassword")
                keyAlias = facturavozSigningProperties.getProperty("keyAlias")
                keyPassword = facturavozSigningProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            if (hasSafeReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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

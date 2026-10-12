import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn("WARNING: android/key.properties not found. Release signing will fail.")
}

val releaseVersionFile = rootProject.file("release-version.properties")
val releaseVersionProperties = Properties().apply {
    if (releaseVersionFile.exists()) {
        releaseVersionFile.inputStream().use { load(it) }
    }
}
val lastUsedReleaseVersionCode =
    releaseVersionProperties.getProperty("lastUsedVersionCode")?.toIntOrNull() ?: 0

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.

    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")

}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}


android {
    namespace = "com.wefilling.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    //ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            if (!keystorePropertiesFile.exists()) {
                error("android/key.properties not found. Create it with storeFile, storePassword, keyAlias, keyPassword.")
            }
            val storeFilePath = keystoreProperties["storeFile"] as String?
                ?: error("storeFile missing in key.properties")
            val resolvedStoreFile = file(storeFilePath)
            if (!resolvedStoreFile.exists()) {
                error("Keystore file not found: $storeFilePath")
            }
            keyAlias = keystoreProperties["keyAlias"] as String?
                ?: error("keyAlias missing in key.properties")
            keyPassword = keystoreProperties["keyPassword"] as String?
                ?: error("keyPassword missing in key.properties")
            storeFile = resolvedStoreFile
            storePassword = keystoreProperties["storePassword"] as String?
                ?: error("storePassword missing in key.properties")
        }
    }

    defaultConfig {
        applicationId = "com.wefilling.app"
        manifestPlaceholders["appLabel"] = "Wefilling"
        minSdkVersion(24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            
            // ProGuard/R8 설정 (코드 난독화 및 최적화)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

val validateReleaseVersion = tasks.register("validateReleaseVersion") {
    group = "release"
    description = "Rejects a release AAB whose versionCode is lower than the latest local release candidate."

    doLast {
        val currentVersionCode = flutter.versionCode
        if (currentVersionCode < lastUsedReleaseVersionCode) {
            throw GradleException(
                "versionCode $currentVersionCode is lower than the latest local release candidate " +
                    "$lastUsedReleaseVersionCode."
            )
        }
        logger.lifecycle(
            "Release: versionName=${flutter.versionName}, " +
                "versionCode=$currentVersionCode, applicationId=com.wefilling.app"
        )
    }
}

val validateReleaseArtifactInputs = tasks.register<Exec>("validateReleaseArtifactInputs") {
    group = "release"
    description = "Runs the fail-closed Wefilling production Release Guard."
    workingDir(rootProject.projectDir.parentFile)
    commandLine(
        "python3",
        rootProject.file("../scripts/release_guard.py").absolutePath,
        "--platform",
        "android",
        "--strict-signing"
    )
}

tasks.configureEach {
    if (name == "bundleRelease") {
        dependsOn(validateReleaseVersion)
        dependsOn(validateReleaseArtifactInputs)
        doLast {
            releaseVersionFile.writeText(
                "lastUsedVersionName=${flutter.versionName}\n" +
                    "lastUsedVersionCode=${flutter.versionCode}\n"
            )
        }
    }
}

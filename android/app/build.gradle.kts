import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

println("--- ОТЛАДКА СБОРКИ ---")
println("Ищу файл настроек здесь: " + keystorePropertiesFile.absolutePath)

if (keystorePropertiesFile.exists()) {
    println("✅ Файл key.properties НАЙДЕН!")
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    
    if (keystoreProperties["storePassword"] == null) {
        println("❌ ОШИБКА: В файле нет строчки 'storePassword'")
    } else {
        println("✅ Пароль storePassword прочитан.")
    }
} else {
    println("❌ ОШИБКА: Файл key.properties НЕ НАЙДЕН по этому пути!")
}
println("------------------------")

android {
    namespace = "ru.gorelovra.tdlroman"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "ru.gorelovra.tdlroman"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            val kPassword = keystoreProperties["keyPassword"] as String?
            val sPassword = keystoreProperties["storePassword"] as String?
            val kAlias = keystoreProperties["keyAlias"] as String?
            val sFile = keystoreProperties["storeFile"] as String?

            if (kPassword != null && sPassword != null && kAlias != null && sFile != null) {
                keyAlias = kAlias
                keyPassword = kPassword
                storeFile = file(sFile)
                storePassword = sPassword
            } else {
                storePassword = "error"
                keyPassword = "error"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
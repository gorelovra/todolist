import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// --- БЛОК ЗАГРУЗКИ КЛЮЧА С ОТЛАДКОЙ ---
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
// ---------------------------------------

android {
    namespace = "com.example.todolist"
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
        applicationId = "com.example.todolist"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
                // Если данных нет, подставляем пустышки, чтобы сборка не падала мгновенно,
                // а мы увидели логи выше. Но сама подпись не сработает.
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
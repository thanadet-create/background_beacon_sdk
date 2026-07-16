group = "com.example.background_beacon_sdk"
version = "0.0.1"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    // AGP 9 มี built-in Kotlin — ไม่ต้อง apply kotlin-android แยก
    id("com.android.library")
}

android {
    namespace = "com.example.background_beacon_sdk"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        // BLE callback scan ใช้ได้ตั้งแต่ 21 — PendingIntent scan (step 5) ต้อง 26+
        minSdk = 21
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // GoogleApiAvailability สำหรับเช็ค GMS — ฝั่ง HMS เช็คผ่าน PackageManager
    // จึงไม่ต้องพึ่ง Huawei SDK/maven repo เลย
    implementation("com.google.android.gms:play-services-base:18.5.0")
}

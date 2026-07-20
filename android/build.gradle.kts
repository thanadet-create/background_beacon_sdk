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
    // AGP 9 ships built-in Kotlin — no separate kotlin-android apply needed
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
        // BLE callback scan works from 21 — PendingIntent scan needs 26+
        minSdk = 21
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // GoogleApiAvailability for the GMS check — the HMS side checks via
    // PackageManager, so no Huawei SDK/maven repo dependency at all
    implementation("com.google.android.gms:play-services-base:18.5.0")
}

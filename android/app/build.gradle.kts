plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "app.sparrowai.sparrow"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.sparrowai.sparrow"
        minSdk = 26
        targetSdk = 35
        versionCode = 20
        versionName = "2.0-test"
    }

    signingConfigs {
        create("sparrow") {
            storeFile = rootProject.file("sparrow.keystore")
            storePassword = "sparrow123"
            keyAlias = "sparrow"
            keyPassword = "sparrow123"
        }
    }

    buildTypes {
        getByName("debug") { signingConfig = signingConfigs.getByName("sparrow") }
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("sparrow")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    // The phone web app (repo root) is bundled into the APK as assets/www
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/web"))
    lint { abortOnError = false; checkReleaseBuilds = false }
}

val copyWeb by tasks.registering(Copy::class) {
    from(rootProject.file("..")) {
        include("index.html", "*.js", "*.css", "manifest.webmanifest", "lib/**", "icons/**", "mascots/**")
        exclude("sw.js")
    }
    into(layout.buildDirectory.dir("generated/web/www"))
}
tasks.named("preBuild") { dependsOn(copyWeb) }

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("com.alphacephei:vosk-android:0.3.47@aar")
    implementation("net.java.dev.jna:jna:5.13.0@aar")
}

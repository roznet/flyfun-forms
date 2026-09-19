import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

android {
    namespace = "aero.flyfun.forms"
    compileSdk = 37

    defaultConfig {
        applicationId = "aero.flyfun.forms"
        minSdk = 33
        targetSdk = 37
        versionCode = 1
        versionName = "0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

// The airport database is a 10 MB SQLite file already committed for the iOS app.
// Copy it into assets at build time rather than committing a second copy:
// a hand-maintained duplicate is exactly the drift this project has been bitten
// by before. See designs/future/android-app-execution.md S0.
//
// Wired through the Variant API (addGeneratedSourceDirectory) because AGP 9
// rejects Provider instances on the legacy SourceSet API -- it cannot tell
// generated from static sources that way, and task dependencies are lost.
abstract class CopyAirportsDb : DefaultTask() {
    @get:InputFile
    abstract val source: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val dir = outputDir.get().asFile
        dir.mkdirs()
        source.get().asFile.copyTo(dir.resolve("airports.db"), overwrite = true)
    }
}

val copyAirportsDb = tasks.register<CopyAirportsDb>("copyAirportsDb") {
    source.set(rootProject.layout.projectDirectory.file("../flyfun-forms/flyfun-forms/airports.db"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copyAirportsDb, CopyAirportsDb::outputDir)
    }
}

dependencies {
    implementation(project(":core-logic"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    implementation(libs.retrofit)
    implementation(libs.retrofit.serialization)
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
}

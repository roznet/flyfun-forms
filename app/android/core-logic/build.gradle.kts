// Pure Kotlin/JVM. Deliberately NO Android dependencies: these are the ported
// logic modules (MRZ, CSV, document resolution, wall-clock) whose Swift tests
// act as the specification, and keeping them Android-free means they run on the
// JVM in milliseconds -- and keeps Kotlin Multiplatform possible later.
// See designs/future/android-app-execution.md S2-S5.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}

tasks.withType<Test>().configureEach {
    testLogging {
        events("passed", "failed", "skipped")
    }
}

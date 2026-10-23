import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// [01] Both apps use this calculation model, so the emissions rules live in one place.
plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.sqldelight)
}

kotlin {
    androidTarget {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }

    // [02] The iPhone and its simulator need separate builds of the same model. Swift receives them as the
    // Shared framework.
    listOf(
        iosArm64(),
        iosSimulatorArm64()
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }

    // [03] Calculation code is shared; each platform supplies its own local database connection.
    sourceSets {
        commonMain.dependencies {
            implementation(libs.sqldelight.runtime)
            implementation(libs.kotlinx.datetime)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
        }
        androidMain.dependencies {
            implementation(libs.sqldelight.androidDriver)
        }
        iosMain.dependencies {
            implementation(libs.sqldelight.nativeDriver)
        }
    }
}

// [04] The database code comes from the saved table definitions, keeping history reads and writes
// consistent.
sqldelight {
    databases {
        create("DFEDatabase") {
            packageName.set("ch.zhaw.digitalfootprintexplorer.database")
        }
    }
}

android {
    namespace = "ch.zhaw.digitalfootprintexplorer.shared"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    defaultConfig {
        minSdk = libs.versions.android.minSdk.get().toInt()
    }
}

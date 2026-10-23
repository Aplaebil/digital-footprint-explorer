// [01] This connects the Android app and the shared model so they can be built together.
rootProject.name = "digitalfootprintexplorer"
enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

// [02] Build tools come from these named sources; Android libraries stay with their expected publisher
// groups.
pluginManagement {
    repositories {
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

// [03] The app libraries use the same source list across both parts of the project.
dependencyResolutionManagement {
    repositories {
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
    }
}

include(":digitalFootprintExplorer-android")
include(":shared")

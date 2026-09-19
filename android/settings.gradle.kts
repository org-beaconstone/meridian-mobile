pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "meridian-sdk-android"

include(":sdk")
include(":app")

project(":sdk").projectDir = file("sdk")
project(":app").projectDir = file("app")

plugins { id("com.android.application"); kotlin("android") }
android {
  namespace = "com.atlassian.meridian"
  compileSdk = 34
  defaultConfig { applicationId = "com.atlassian.meridian"; minSdk = 24; targetSdk = 34; versionCode = 1; versionName = "1.0" }
  buildFeatures { compose = true }
  composeOptions { kotlinCompilerExtensionVersion = "1.5.8" }
  compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
  kotlinOptions { jvmTarget = "17" }
}
dependencies {
  implementation(project(":sdk"))
  implementation("androidx.activity:activity-compose:1.8.2")
  implementation("androidx.compose.material:material:1.5.4")
  implementation("androidx.compose.foundation:foundation:1.5.4")
  implementation("androidx.compose.ui:ui:1.5.4")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

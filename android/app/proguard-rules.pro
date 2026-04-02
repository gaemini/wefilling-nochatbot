# ──────────────────────────────────────────────
# AndroidX @Keep annotation support
# ──────────────────────────────────────────────
-keep,allowobfuscation @interface androidx.annotation.Keep
-keep @androidx.annotation.Keep class *
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# ──────────────────────────────────────────────
# Google Sign-In & Firebase Auth
# ──────────────────────────────────────────────
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# ──────────────────────────────────────────────
# Firebase Cloud Messaging (FCM)
# ──────────────────────────────────────────────
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }
-dontwarn com.google.firebase.messaging.**
-dontwarn com.google.firebase.iid.**
-keep class io.flutter.plugins.firebase.messaging.** { *; }

# ──────────────────────────────────────────────
# Flutter Local Notifications
# ──────────────────────────────────────────────
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ──────────────────────────────────────────────
# Permission Handler (알림 권한 다이얼로그)
# ──────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**
-keep class com.baseflow.** { *; }
-dontwarn com.baseflow.**

# ──────────────────────────────────────────────
# Flutter core
# ──────────────────────────────────────────────
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# ──────────────────────────────────────────────
# Kotlin (Firebase 플러그인 내부에서 사용)
# ──────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ──────────────────────────────────────────────
# Attributes & metadata
# ──────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses,EnclosingMethod

# ──────────────────────────────────────────────
# Exception classes (crash reports)
# ──────────────────────────────────────────────
-keep public class * extends java.lang.Exception

# ──────────────────────────────────────────────
# Gson
# ──────────────────────────────────────────────
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# ──────────────────────────────────────────────
# Logging (릴리스 빌드에서 제거)
# ──────────────────────────────────────────────
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# ──────────────────────────────────────────────
# Native methods
# ──────────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ──────────────────────────────────────────────
# App model classes
# ──────────────────────────────────────────────
-keep class com.wefilling.app.** { *; }

# ──────────────────────────────────────────────
# Play Core (split APKs / deferred components)
# ──────────────────────────────────────────────
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**


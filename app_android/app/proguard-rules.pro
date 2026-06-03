# =====================================================================
# proguard-rules.pro — regras de R8/ProGuard para o release.
# =====================================================================

# ---- kotlinx.serialization ----
# Mantém os serializers gerados e os companions @Serializable.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Mantém serializers das nossas classes @Serializable (modelos do protocolo/QR).
-keep,includedescriptorclasses class com.dantetesta.dantecast.**$$serializer { *; }
-keepclassmembers class com.dantetesta.dantecast.** {
    *** Companion;
}
-keepclasseswithmembers class com.dantetesta.dantecast.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ---- ML Kit barcode ----
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# ---- CameraX ----
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Mantém nomes de classes/membros usados via reflexão pelo Compose tooling (debug-only, mas seguro).
-dontwarn org.jetbrains.annotations.**

# Preserve generic signatures for reflection (Fixes TypeToken error)
-keepattributes Signature,Exceptions,*Annotation*,InnerClasses,EnclosingMethod

# Flutter Local Notifications rules
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Firebase rules
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Sign In rules
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.auth.api.signin.**

# Sqflite rules
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# GSON rules (if used by any plugin)
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# OTA Update rules
-keep class sk.fourq.otaupdate.** { *; }
-dontwarn sk.fourq.otaupdate.**

# ML Kit Text Recognition missing classes rules
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# General ML Kit rules
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text_common.**

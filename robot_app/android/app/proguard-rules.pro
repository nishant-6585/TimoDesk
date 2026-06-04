# Keep Netty classes (for CsjRobot SDK)
-keep class io.netty.** { *; }
-dontwarn io.netty.**

# Keep javax annotations
-keep class javax.annotation.** { *; }
-dontwarn javax.annotation.**

# Keep java.lang.invoke (for lambdas)
-keep class java.lang.invoke.** { *; }
-dontwarn java.lang.invoke.**

# Keep okhttp and retrofit
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**

# Keep CsjBot SDK
-keep class com.csjbot.** { *; }
-dontwarn com.csjbot.**

# Keep Flutter
-keep class io.flutter.** { *; }

# Keep JSON
-keep class org.json.** { *; }

# Disable R8 shrinking for these packages
-dontshrink

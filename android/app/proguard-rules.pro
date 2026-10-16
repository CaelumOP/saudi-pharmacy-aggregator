# Keep rules for CameraX and ML Kit reflection in mobile_scanner
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**

# Keep rules for Chromium WebKit / InAppWebView
-keep class androidx.webkit.** { *; }
-dontwarn androidx.webkit.**

-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**

# APX PRO — R8/ProGuard keep rules for the release build.
#
# Flutter's own engine rules are applied automatically by the Flutter Gradle
# plugin; this file only adds keeps for reflection-heavy third-party SDKs that
# R8 would otherwise strip or rename, breaking them at runtime.

# ── Razorpay (payments) ───────────────────────────────────────────────────────
# Razorpay's checkout uses a WebView + JS bridge and reflection; without these
# keeps the payment flow crashes in release builds. (Rules per Razorpay docs.)
-keep class com.razorpay.** { *; }
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
-optimizations !method/inlining/*
-dontwarn com.razorpay.**

# ── Google Play Core (deferred components / split installs) ────────────────────
# Flutter references these classes; keep them to avoid "missing class" R8 errors.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── General annotation/signature safety for plugins using reflection ───────────
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod

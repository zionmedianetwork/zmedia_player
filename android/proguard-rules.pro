# ProGuard Rules for ZMedia Player
# Ensures proper functionality in Android release builds with code minification

# ============================================================================
# ZMedia Player Plugin
# ============================================================================

# Keep all plugin classes and their public methods
-keep class com.zionmedianetwork.zmedia_player.** { *; }
-keepclassmembers class com.zionmedianetwork.zmedia_player.** {
    public *;
    protected *;
}

# Keep method channel handler methods
-keepclassmembers class com.zionmedianetwork.zmedia_player.ZMediaPlayerPlugin {
    public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel.Result);
    public void onAttachedToEngine(io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding);
    public void onDetachedFromEngine(io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding);
}

# Keep platform view factory
-keep class com.zionmedianetwork.zmedia_player.MediaPlayerViewFactory { *; }
-keepclassmembers class com.zionmedianetwork.zmedia_player.MediaPlayerViewFactory {
    public <init>(...);
}

# ============================================================================
# ExoPlayer / AndroidX Media3
# ============================================================================

# Keep all ExoPlayer classes
-keep class com.google.android.exoplayer2.** { *; }
-keep interface com.google.android.exoplayer2.** { *; }
-keepclassmembers class com.google.android.exoplayer2.** {
    *;
}

# Don't warn about ExoPlayer
-dontwarn com.google.android.exoplayer2.**

# Keep ExoPlayer DataSource and MediaSource implementations
-keep class * extends com.google.android.exoplayer2.upstream.DataSource { *; }
-keep class * extends com.google.android.exoplayer2.source.MediaSource { *; }

# Keep ExoPlayer Renderer implementations
-keep class * extends com.google.android.exoplayer2.Renderer { *; }
-keep class * extends com.google.android.exoplayer2.RendererCapabilities { *; }

# Keep ExoPlayer extractor implementations
-keep class * extends com.google.android.exoplayer2.extractor.Extractor { *; }

# ============================================================================
# DRM (Digital Rights Management)
# ============================================================================

# Keep all DRM-related classes
-keep class com.google.android.exoplayer2.drm.** { *; }
-keep interface com.google.android.exoplayer2.drm.** { *; }
-keepclassmembers class com.google.android.exoplayer2.drm.** {
    *;
}

# Don't warn about DRM
-dontwarn com.google.android.exoplayer2.drm.**

# Keep MediaDrm classes
-keep class android.media.MediaDrm { *; }
-keep class android.media.MediaDrm$** { *; }

# Keep DRM scheme UUIDs (critical for DRM to work)
-keepclassmembers class com.google.android.exoplayer2.C {
    public static final java.util.UUID WIDEVINE_UUID;
    public static final java.util.UUID PLAYREADY_UUID;
    public static final java.util.UUID CLEARKEY_UUID;
}

# ============================================================================
# Google Cast (Chromecast)
# ============================================================================

# Keep Cast Framework classes
-keep class com.google.android.gms.cast.** { *; }
-keep interface com.google.android.gms.cast.** { *; }
-keepclassmembers class com.google.android.gms.cast.** {
    *;
}

# Don't warn about Cast
-dontwarn com.google.android.gms.cast.**

# Keep CastOptionsProvider
-keep class * implements com.google.android.gms.cast.framework.OptionsProvider { *; }
-keep class com.zionmedianetwork.zmedia_player.CastOptionsProvider { *; }

# ============================================================================
# Flutter Framework
# ============================================================================

# Keep all Flutter classes
-keep class io.flutter.** { *; }
-keep interface io.flutter.** { *; }
-keepclassmembers class io.flutter.** {
    *;
}

# Keep Flutter plugin classes
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep platform views
-keep class io.flutter.plugin.platform.** { *; }
-keepclassmembers class io.flutter.plugin.platform.** {
    *;
}

# Keep method channel classes
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$** { *; }
-keepclassmembers class io.flutter.plugin.common.MethodChannel {
    *;
}

# Keep method channel result callbacks
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel.Result *;
}

# Keep binary messenger
-keep class io.flutter.plugin.common.BinaryMessenger { *; }
-keep class io.flutter.plugin.common.BinaryMessenger$** { *; }

# ============================================================================
# AndroidX Libraries
# ============================================================================

# Keep all AndroidX classes
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# Keep AndroidX Media (for notifications)
-keep class androidx.media.** { *; }
-keep interface androidx.media.** { *; }

# Keep AndroidX Lifecycle
-keep class androidx.lifecycle.** { *; }
-keep interface androidx.lifecycle.** { *; }

# ============================================================================
# Kotlin
# ============================================================================

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata {
    *;
}

# Keep Kotlin when mappings (for when expressions)
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# Keep Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Don't warn about Kotlin
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ============================================================================
# Java/Android Core
# ============================================================================

# Keep native methods
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep custom views constructors
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet);
}

-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# Keep view getters/setters
-keepclassmembers public class * extends android.view.View {
    void set*(***);
    *** get*();
}

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ============================================================================
# Media & Video Processing
# ============================================================================

# Keep media codec classes
-keep class android.media.MediaCodec { *; }
-keep class android.media.MediaCodec$** { *; }

# Keep media format classes
-keep class android.media.MediaFormat { *; }
-keep class android.media.MediaFormat$** { *; }

# Keep media extractor
-keep class android.media.MediaExtractor { *; }
-keep class android.media.MediaExtractor$** { *; }

# ============================================================================
# Network & HTTP
# ============================================================================

# Keep HTTP data source factories
-keep class * extends com.google.android.exoplayer2.upstream.HttpDataSource$Factory { *; }
-keep class com.google.android.exoplayer2.upstream.DefaultHttpDataSource { *; }
-keep class com.google.android.exoplayer2.upstream.DefaultHttpDataSource$** { *; }

# ============================================================================
# Reflection & Annotations
# ============================================================================

# Keep annotated classes and methods
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep source file names and line numbers for better stack traces
-keepattributes SourceFile,LineNumberTable

# Keep runtime visible annotations
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeVisibleTypeAnnotations

# ============================================================================
# Optimization Settings
# ============================================================================

# Don't optimize code too aggressively (can cause issues with media playback)
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*

# Allow optimization but preserve critical functionality
-optimizationpasses 5
-allowaccessmodification

# Don't preverify (not needed for Android)
-dontpreverify

# ============================================================================
# Debugging & Logging
# ============================================================================

# Keep crash reporting classes
-keep class com.zionmedianetwork.zmedia_player.CrashHandler { *; }
-keepclassmembers class com.zionmedianetwork.zmedia_player.CrashHandler {
    *;
}

# Remove logging in release builds (optional - comment out to keep logs)
# -assumenosideeffects class android.util.Log {
#     public static *** d(...);
#     public static *** v(...);
#     public static *** i(...);
# }

# ============================================================================
# Warnings to Suppress
# ============================================================================

# Suppress warnings that are safe to ignore
-dontwarn org.xmlpull.v1.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**

# Flutter Play Core (deferred components - not used by this plugin)
-dontwarn com.google.android.play.core.**

# Keep Play Core classes if they exist (optional - Flutter may use them)
-keep class com.google.android.play.core.** { *; }

# If Play Core is not included, don't fail the build
-dontnote com.google.android.play.core.**

# ============================================================================
# Additional Safety Rules
# ============================================================================

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep class name for debugging
-keepnames class * { *; }

# Print mapping to file for debugging crashes
-printmapping mapping.txt

# ============================================================================
# END OF PROGUARD RULES
# ============================================================================


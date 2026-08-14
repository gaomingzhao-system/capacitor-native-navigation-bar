# Capacitor discovers plugin methods reflectively through the @CapacitorPlugin /
# @PluginMethod annotations, so the plugin class and its bridge methods must
# survive shrinking. Shipped as a consumer rule so apps get it automatically.
-keep class app.nativenavigationbar.capacitor.NativeNavigationPlugin { *; }
-keepclassmembers class app.nativenavigationbar.capacitor.** {
    @com.getcapacitor.PluginMethod <methods>;
}
-keep @com.getcapacitor.annotation.CapacitorPlugin class * { *; }

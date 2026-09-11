# Release builds run R8, which strips classes it cannot see being used.

# flutter_callkit_incoming is started by the system (notifications and the
# full-screen incoming-call activity) and serialises call data by reflection.
# The plugin already ships these rules as consumer rules; they are repeated
# here because its README asks for them, so the protection does not silently
# depend on the plugin's packaging.
-keep class com.hiennv.flutter_callkit_incoming.** { *; }

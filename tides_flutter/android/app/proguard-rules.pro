# Preserve generic type signatures used by Gson's TypeToken.
# Without this, R8 strips the Signature attribute from anonymous TypeToken
# subclasses and Gson throws RuntimeException("Missing type parameter.") when
# deserializing scheduled notification data (FLN's loadScheduledNotifications).
-keepattributes Signature

# Keep TypeToken itself and every anonymous subclass (the token carriers).
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# FLN's model classes used in Gson serialization — must not be renamed or
# stripped, as field names are matched against JSON keys at runtime.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Standard Gson annotation retention.
-keepattributes *Annotation*
-dontwarn sun.misc.**

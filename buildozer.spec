[app]

# App title and identity
title = Tides
package.name = tides
package.domain = org.silas

# Source
source.dir = .
source.include_exts = py,kv,json,png,jpg
source.exclude_dirs = tests, bin, __pycache__

version = 1.0

# Dependencies — stdlib only; Kivy ships its own Python on Android
requirements = python3,kivy

# Orientation
orientation = portrait

# Permissions
android.permissions = INTERNET

# API levels
android.api = 33
android.minapi = 26
android.ndk = 25b

# Both arches: arm64-v8a for real phones, x86_64 for emulator testing
android.archs = arm64-v8a, x86_64

# Enable AndroidX
android.enable_androidx = True

icon.filename = %(source.dir)s/tides_icon.png

# Fullscreen — False keeps the system status bar visible
fullscreen = 0

[buildozer]
log_level = 2
warn_on_root = 1

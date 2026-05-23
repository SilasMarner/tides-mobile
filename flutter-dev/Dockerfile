FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android
ENV FLUTTER_HOME=/opt/flutter
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=$PATH:$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
ENV PUB_CACHE=/data/pub-cache

RUN apt-get update && apt-get install -y \
    git curl unzip xz-utils zip wget sudo \
    libglu1-mesa libpulse0 \
    openjdk-17-jdk && \
    rm -rf /var/lib/apt/lists/*

# Flutter SDK (stable)
RUN git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FLUTTER_HOME && \
    flutter precache --android && \
    flutter config --no-analytics

# Android command-line tools
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
         -O /tmp/cmdtools.zip && \
    unzip -q /tmp/cmdtools.zip -d $ANDROID_HOME/cmdline-tools && \
    mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm /tmp/cmdtools.zip

# Android SDK platforms + licenses
RUN yes | sdkmanager --licenses > /dev/null && \
    sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# code-server (VS Code in browser)
RUN curl -fsSL https://code-server.dev/install.sh | sh && \
    code-server --install-extension Dart-Code.flutter --force

RUN mkdir -p /workspace /data/pub-cache /data/gradle
WORKDIR /workspace

EXPOSE 8080

CMD ["code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "none", "/workspace"]

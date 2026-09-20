FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG GODOT_VERSION=4.7.2

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_HOME=/opt/android-sdk \
    JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 \
    GODOT_VERSION=${GODOT_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
      unzip curl ca-certificates wget \
      # Godot needs these even for a headless export: the editor binary links
      # against them unconditionally.
      libfontconfig1 libxi6 libxrandr2 libxinerama1 libxcursor1 libgl1 \
    && rm -rf /var/lib/apt/lists/*

# JDK 21. Godot's Gradle build does not support 25.
RUN mkdir -p /etc/apt/keyrings \
    && wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" \
      > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update && apt-get install -y --no-install-recommends temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*

# Android SDK: command-line tools, plus the platform and build-tools the
# Godot Android exporter resolves against.
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline.zip \
      https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q /tmp/cmdline.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline.zip \
    && yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null \
    && "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
         "platform-tools" "platforms;android-36" "build-tools;36.0.0" > /dev/null

# Godot plus its export templates, pinned to the same version.
RUN base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable" \
    && curl -fsSL -o /tmp/godot.zip "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && curl -fsSL -o /tmp/templates.tpz "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    && unzip -q /tmp/templates.tpz -d /tmp/tpl \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && mv /tmp/tpl/templates/* "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/" \
    && mkdir -p "/home/vscode/.local/share/godot/export_templates" \
    && cp -r "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
             "/home/vscode/.local/share/godot/export_templates/" \
    && chown -R vscode:vscode /home/vscode/.local \
    && rm -rf /tmp/godot.zip /tmp/templates.tpz /tmp/tpl

RUN curl -fsSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin

ENV PATH="${PATH}:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/cmdline-tools/latest/bin"

FROM ubuntu:22.04

# Avoid timezone prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential dependencies and a headless browser
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    chromium-browser \
    && rm -rf /var/lib/apt/lists/*

# Download and install the latest stable Flutter SDK
RUN git clone https://github.com/flutter/flutter.git -b stable /opt/flutter

# Add Flutter to the system PATH
ENV PATH="/opt/flutter/bin:$PATH"

# Pre-authorize the workspace directory to avoid Git ownership errors
RUN git config --global --add safe.directory /workspace

# Initialize Flutter and download Dart SDK
RUN flutter doctor

# Set the default working directory for when you enter the container
WORKDIR /workspace

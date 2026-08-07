FROM ghcr.io/cirruslabs/flutter:3.44.6

# Pinned development image. Production builds use Dockerfile.backend and
# Dockerfile.frontend; this image is retained for interactive Flutter work.
RUN git config --global --add safe.directory /workspace
WORKDIR /workspace

CMD ["flutter", "doctor", "-v"]

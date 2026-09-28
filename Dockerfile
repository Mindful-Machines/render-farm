ARG RCLONE_VERSION=1.75.1

FROM ubuntu:24.04 AS base

ARG FLAMENCO_VERSION=3.9.3

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/flamenco \
    && curl -fsSL https://flamenco.blender.org/downloads/flamenco-${FLAMENCO_VERSION}-linux-amd64.tar.gz \
       | tar -xz -C /opt/flamenco --strip-components=1

WORKDIR /opt/flamenco


FROM base AS manager

# Config edits in the web UI are lost when the container is recreated: edit src/ and rebuild.
COPY src/flamenco-manager.yaml ./
COPY src/blender_render_frames.js ./scripts/

EXPOSE 8080
HEALTHCHECK CMD curl -fs http://localhost:8080/api/v3/version || exit 1
ENTRYPOINT ["./flamenco-manager"]


FROM base AS worker

ARG BLENDER_VERSION=5.2.2
ARG TAILSCALE_VERSION=1.102.4

# Headless Blender libraries.
RUN apt-get update && apt-get install -y --no-install-recommends \
      xz-utils \
      libgl1 libegl1 libxi6 libxkbcommon0 libxrender1 libsm6 libxxf86vm1 libxfixes3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/blender-${BLENDER_VERSION} \
    && curl -fsSL https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/blender-${BLENDER_VERSION}-linux-x64.tar.xz \
       | tar -xJ -C /opt/blender-${BLENDER_VERSION} --strip-components=1

RUN mkdir -p /opt/tailscale \
    && curl -fsSL https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz \
       | tar -xz -C /opt/tailscale --strip-components=1

COPY src/enable_gpu.py src/entrypoint.sh /opt/farm/

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    BLENDER=/opt/blender-${BLENDER_VERSION}/blender

ENTRYPOINT ["bash", "/opt/farm/entrypoint.sh"]


FROM rclone/rclone:${RCLONE_VERSION} AS sync

COPY src/farm-sync.sh /usr/local/bin/farm-sync
ENTRYPOINT ["farm-sync"]

# syntax=docker/dockerfile:1

# ---- Pinned versions. To upgrade: bump the version AND its checksum/commit. ----
ARG PI_VERSION=1.1.0
# sha256 of pi-${PI_VERSION}-source.tar.gz (from the release's SHA256SUMS)
ARG PI_SOURCE_SHA256=63b17b48b855e36e64c5013523acd48131ffcfa90ae48fe2f3e6fa9fe3d0da32
# Pi's release workflow builds with this bun version
ARG BUN_VERSION=1.3.14
ARG BUN_SHA256=951ee2aee855f08595aeec6225226a298d3fea83a3dcd6465c09cbccdf7e848f
ARG RTK_VERSION=v0.51.0
# Commit the rtk tag must resolve to (guards against a moved tag)
ARG RTK_COMMIT=e001f773f80b22b7dc4c7a79521b30e35aaef026

# ---- Pi: built from the checksum-verified release source archive ----
FROM node:24-trixie-slim AS pi-build
ARG PI_VERSION
ARG PI_SOURCE_SHA256
ARG BUN_VERSION
ARG BUN_SHA256
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN curl -fsSL -o bun.zip "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64.zip" \
 && echo "${BUN_SHA256}  bun.zip" | sha256sum -c - \
 && unzip -q bun.zip && install -m 0755 bun-linux-x64/bun /usr/local/bin/bun
RUN curl -fsSL -o pi.tar.gz "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-${PI_VERSION}-source.tar.gz" \
 && echo "${PI_SOURCE_SHA256}  pi.tar.gz" | sha256sum -c - \
 && tar -xzf pi.tar.gz
# npm ci (run by the script) installs from the lockfile with --ignore-scripts
RUN cd "pi-${PI_VERSION}" \
 && ./scripts/build-binaries.sh --offline-model-data --platform linux-x64 --out /out

# ---- rtk: built from source, pinned tag + commit, locked deps ----
# (not `cargo install rtk`: that crate name belongs to an unrelated project)
FROM rust:1-trixie AS rtk-build
ARG RTK_VERSION
ARG RTK_COMMIT
RUN git clone --depth 1 --branch "${RTK_VERSION}" https://github.com/rtk-ai/rtk /rtk \
 && cd /rtk \
 && test "$(git rev-parse HEAD)" = "${RTK_COMMIT}" \
 && cargo build --release --locked

# ---- Runtime: no compilers, curl, or npm ----
FROM debian:trixie-slim
# Tools available to the agent. Add more apt packages here.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates fd-find git ripgrep \
 && rm -rf /var/lib/apt/lists/*
COPY --from=pi-build /out/linux-x64/ /opt/pi/
COPY --from=rtk-build /rtk/target/release/rtk /usr/local/bin/rtk
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN ln -s /opt/pi/pi /usr/local/bin/pi \
 && chmod 0755 /usr/local/bin/entrypoint.sh \
 && useradd --uid 10001 --user-group --no-create-home --home-dir /home/pi --shell /usr/sbin/nologin pi \
 && mkdir -p /workspace /home/pi/.pi && chown 10001:10001 /workspace /home/pi/.pi
ENV HOME=/home/pi \
    PI_CODING_AGENT_DIR=/home/pi/.pi/agent \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0
USER 10001:10001
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

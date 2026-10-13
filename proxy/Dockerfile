FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Debian's squid package creates the unprivileged `proxy` user
USER proxy
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

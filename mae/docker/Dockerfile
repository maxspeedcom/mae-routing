# MAE Routing container image (ghcr.io/maxspeedcom/mae-routing)
# Binaries are cross-compiled beforehand into dist/linux_<arch>/ (see .github/workflows/mae-docker.yml).
FROM alpine:3.22
RUN apk add --no-cache ca-certificates iptables ip6tables iproute2 \
 && rm /usr/sbin/iptables /usr/sbin/ip6tables \
 && ln -s /usr/sbin/iptables-legacy /usr/sbin/iptables \
 && ln -s /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables
ARG TARGETARCH
COPY dist/linux_${TARGETARCH}/ /usr/local/bin/
COPY mae/docker/entrypoint.sh /usr/local/bin/mae-routing-entrypoint
# containerboot (from upstream) starts "tailscaled" and runs "tailscale up": point those names at ours
RUN ln -s mae-routing /usr/local/bin/tailscale \
 && ln -s mae-routingd /usr/local/bin/tailscaled \
 && chmod 755 /usr/local/bin/mae-routing-entrypoint \
 && mkdir -p /var/lib/mae-routing /var/run/mae-routing
LABEL org.opencontainers.image.title="MAE Routing" \
      org.opencontainers.image.description="Connect a container or host to your organisation's MAE Routing network" \
      org.opencontainers.image.url="https://routing.maesuaisystem.com/" \
      org.opencontainers.image.source="https://github.com/maxspeedcom/mae-routing" \
      org.opencontainers.image.licenses="BSD-3-Clause"
VOLUME /var/lib/mae-routing
ENTRYPOINT ["/usr/local/bin/mae-routing-entrypoint"]

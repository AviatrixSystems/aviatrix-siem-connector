FROM alpine:3.24.4
LABEL org.opencontainers.image.source="https://github.com/AviatrixSystems/aviatrix-siem-connector"
LABEL org.opencontainers.image.description="stunnel mTLS sidecar for Aviatrix SIEM Connector"
# Set STUNNEL_VERSION (an apk version string, e.g. 5.x.y-r0) to pin stunnel.
ARG STUNNEL_VERSION=""
RUN if [ -n "$STUNNEL_VERSION" ]; then apk add --no-cache "stunnel=$STUNNEL_VERSION"; \
    else apk add --no-cache stunnel; fi
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

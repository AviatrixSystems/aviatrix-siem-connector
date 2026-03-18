FROM alpine:3.21
LABEL org.opencontainers.image.source="https://github.com/aviatrixsystems/log-integration-engine"
LABEL org.opencontainers.image.description="stunnel mTLS sidecar for Aviatrix SIEM Connector"
RUN apk add --no-cache stunnel
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

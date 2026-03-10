FROM alpine:3.21
RUN apk add --no-cache stunnel
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

FROM docker.elastic.co/logstash/logstash:8.16.2

ARG EXTRA_PLUGINS=""
RUN if [ -n "$EXTRA_PLUGINS" ]; then logstash-plugin install $EXTRA_PLUGINS; fi

# No COPY --chmod: BuildKit applies it to directories too (untraversable dirs).
USER root
COPY pipeline/ /usr/share/logstash/pipeline/
COPY patterns/ /usr/share/logstash/patterns/
RUN chmod -R a+rX,go-w /usr/share/logstash/pipeline /usr/share/logstash/patterns
USER 1000

FROM docker.elastic.co/logstash/logstash:8.16.2

ARG EXTRA_PLUGINS=""
RUN if [ -n "$EXTRA_PLUGINS" ]; then logstash-plugin install $EXTRA_PLUGINS; fi

COPY --chmod=644 pipeline/ /usr/share/logstash/pipeline/
COPY --chmod=644 patterns/ /usr/share/logstash/patterns/

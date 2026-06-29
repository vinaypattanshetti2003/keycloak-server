FROM quay.io/keycloak/keycloak:26.2

ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_HTTP_ENABLED=true
ENV KC_DB=postgres

RUN /opt/keycloak/bin/kc.sh build

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["exec /opt/keycloak/bin/kc.sh start --optimized --http-port=${PORT:-8080}"]

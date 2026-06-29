FROM quay.io/keycloak/keycloak:26.2

ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

COPY start.sh /start.sh

RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
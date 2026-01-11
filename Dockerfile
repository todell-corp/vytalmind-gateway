FROM envoyproxy/envoy:v1.32.2

# Install gettext for envsubst command and curl for health checks
RUN apt-get update && apt-get install -y gettext-base curl && rm -rf /var/lib/apt/lists/*

COPY envoy.yaml /etc/envoy/envoy.yaml

EXPOSE 443 9901

CMD ["/usr/local/bin/envoy", "-c", "/etc/envoy/envoy.yaml"]

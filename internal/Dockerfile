FROM envoyproxy/envoy:v1.31-latest

# Copy configuration
COPY config/ /etc/envoy/config/

# Create directories for logs (certs come from vault-agent shared volume)
RUN mkdir -p /var/log/envoy

# Use default Envoy entrypoint
ENTRYPOINT ["/usr/local/bin/envoy"]

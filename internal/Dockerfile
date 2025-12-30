FROM envoyproxy/envoy:v1.31-latest

# Install Vault CLI and utilities
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - \
    && echo "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y vault \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration
COPY config/ /etc/envoy/config/

# Create directories
RUN mkdir -p /etc/envoy/certs /var/log/envoy

# Make scripts executable
RUN chmod +x /etc/envoy/config/bootstrap/vault-mtls-init.sh
RUN chmod +x /etc/envoy/config/cert-renewal.sh

ENTRYPOINT ["/etc/envoy/config/bootstrap/vault-mtls-init.sh"]

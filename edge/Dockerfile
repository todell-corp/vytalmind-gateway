FROM envoyproxy/envoy:v1.31-latest

# Install necessary tools for Vault integration
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Vault CLI for certificate fetching
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - \
    && echo "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y vault \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY config/ /etc/envoy/config/

# Create directories for certs and logs
RUN mkdir -p /etc/envoy/certs /var/log/envoy

# Make bootstrap script executable
RUN chmod +x /etc/envoy/config/bootstrap/vault-tls-init.sh

# Entry point: Fetch certs from Vault, then start Envoy
ENTRYPOINT ["/etc/envoy/config/bootstrap/vault-tls-init.sh"]

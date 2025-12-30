# Prometheus Configuration for External Prometheus

This directory contains the Prometheus scrape configuration for the VytalMind Gateway.

Since we're using the existing Prometheus deployment at **https://prometheus.odell.com**, you'll need to add these scrape jobs to your Prometheus configuration.

## Scrape Jobs to Add

Add the following to your Prometheus configuration at prometheus.odell.com:

```yaml
scrape_configs:
  # Edge Envoy metrics
  - job_name: 'vytalmind-edge-envoy'
    metrics_path: /stats/prometheus
    static_configs:
      - targets: ['<edge-envoy-host>:9901']
        labels:
          service: 'edge-envoy'
          tier: 'edge'
          project: 'vytalmind-gateway'

  # Internal Envoy metrics
  - job_name: 'vytalmind-internal-envoy'
    metrics_path: /stats/prometheus
    static_configs:
      - targets: ['<internal-envoy-host>:9902']
        labels:
          service: 'internal-envoy'
          tier: 'internal'
          project: 'vytalmind-gateway'

  # Redis metrics (optional - requires redis_exporter)
  - job_name: 'vytalmind-redis'
    static_configs:
      - targets: ['<redis-host>:6379']
        labels:
          service: 'redis'
          project: 'vytalmind-gateway'
```

## Accessing Metrics

### From Localhost (Development)

If running locally, you can access the metrics endpoints directly:

- **Edge Envoy**: http://localhost:9901/stats/prometheus
- **Internal Envoy**: http://localhost:9902/stats/prometheus

### From Prometheus Server

Ensure your Prometheus server at prometheus.odell.com can reach:
- The edge Envoy admin port (9901)
- The internal Envoy admin port (9902)

You may need to:
1. Configure network access/firewall rules
2. Use host networking mode
3. Set up a proxy for metrics endpoints
4. Configure Prometheus service discovery

## Key Metrics to Monitor

### Request Metrics
- `envoy_http_downstream_rq_total` - Total requests
- `envoy_http_downstream_rq_xx` - Requests by response code (2xx, 4xx, 5xx)
- `envoy_http_downstream_rq_time_bucket` - Request latency histogram

### Connection Metrics
- `envoy_http_downstream_cx_total` - Total connections
- `envoy_http_downstream_cx_active` - Active connections
- `envoy_http_downstream_cx_destroy_remote` - Connections destroyed by remote

### Upstream Metrics
- `envoy_cluster_upstream_rq_total` - Upstream requests per cluster
- `envoy_cluster_upstream_rq_time` - Upstream request latency
- `envoy_cluster_upstream_cx_connect_fail` - Upstream connection failures

### TLS Metrics
- `envoy_listener_ssl_connection_error` - TLS handshake errors
- `envoy_ssl_ciphers` - Cipher usage statistics

### Health Metrics
- `envoy_server_live` - Server is live (1 = healthy)
- `envoy_server_memory_allocated` - Memory usage
- `envoy_server_uptime` - Server uptime in seconds

## Grafana Dashboards

Consider importing these community dashboards:
- **Envoy Global**: Dashboard ID 11021
- **Envoy Clusters**: Dashboard ID 11022

Or create custom dashboards based on your specific needs.

## Example Queries

```promql
# Request rate per service
rate(envoy_http_downstream_rq_total[5m])

# Error rate (5xx responses)
rate(envoy_http_downstream_rq_xx{envoy_response_code_class="5"}[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(envoy_http_downstream_rq_time_bucket[5m]))

# Active connections
envoy_http_downstream_cx_active

# JWT authentication failures
rate(envoy_http_jwt_authn_failure[5m])
```

## Network Configuration

If your Envoy containers are running on a different host than Prometheus, you'll need to ensure network connectivity. Options include:

1. **Direct Access**: Open firewall ports 9901 and 9902
2. **Internal Service Discovery**: Use internal service discovery
3. **Gateway Proxy**: Expose metrics through a gateway
4. **Prometheus Agent**: Run a Prometheus agent locally that forwards to central Prometheus

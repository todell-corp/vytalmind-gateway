FROM envoyproxy/envoy:v1.32.2

COPY envoy.yaml /etc/envoy/envoy.yaml

EXPOSE 443 9901

CMD ["/usr/local/bin/envoy", "-c", "/etc/envoy/envoy.yaml"]

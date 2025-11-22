kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  kubeProxyMode: "iptables"
nodes:
  - role: control-plane
%{ if length(ports) > 0 ~}
    extraPortMappings:
%{ for port in ports ~}
      - containerPort: ${port.container_port}
        hostPort: ${port.host_port}
        protocol: ${port.protocol}
%{ endfor ~}
%{ endif ~}
%{ for _ in workers ~}
  - role: worker
%{ endfor ~}

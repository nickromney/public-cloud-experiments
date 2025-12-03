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
%{ if length(extra_mounts) > 0 ~}
    extraMounts:
%{ for mnt in extra_mounts ~}
      - hostPath: ${mnt.host_path}
        containerPath: ${mnt.container_path}
        readOnly: ${mnt.read_only}
%{ endfor ~}
%{ endif ~}
%{ endif ~}
%{ for _ in workers ~}
  - role: worker
%{ if length(extra_mounts) > 0 ~}
    extraMounts:
%{ for mnt in extra_mounts ~}
      - hostPath: ${mnt.host_path}
        containerPath: ${mnt.container_path}
        readOnly: ${mnt.read_only}
%{ endfor ~}
%{ endif ~}
%{ endfor ~}

kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  kubeProxyMode: "iptables"
%{ if length(extra_mounts) > 0 ~}
containerdConfigPatches:
  - |-
%{ for mnt in extra_mounts ~}
%{ if try(mnt.registry_host, "") != "" ~}
    [plugins."io.containerd.grpc.v1.cri".registry.configs."${mnt.registry_host}".tls]
      ca_file = "${mnt.container_path}"
%{ endif ~}
%{ endfor ~}
%{ endif ~}
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
%{ if length(extra_mounts) > 0 ~}
    extraMounts:
%{ for mnt in extra_mounts ~}
      - hostPath: ${mnt.host_path}
        containerPath: ${mnt.container_path}
        readOnly: ${mnt.read_only}
%{ endfor ~}
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

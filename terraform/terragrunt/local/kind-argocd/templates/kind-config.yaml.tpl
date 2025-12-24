kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: ${api_server_port}
  disableDefaultCNI: true
  kubeProxyMode: "iptables"
%{ if length(extra_mounts) > 0 || try(insecure_registry, "") != "" || (try(dockerhub_username, "") != "" && try(dockerhub_password, "") != "") || try(dockerhub_mirror_endpoint, "") != "" ~}
containerdConfigPatches:
  - |-
%{ for mnt in extra_mounts ~}
%{ if try(mnt.registry_host, "") != "" ~}
    [plugins."io.containerd.grpc.v1.cri".registry.configs."${mnt.registry_host}".tls]
      ca_file = "${mnt.container_path}"
%{ endif ~}
%{ endfor ~}
%{ if try(insecure_registry, "") != "" ~}
    [plugins."io.containerd.grpc.v1.cri".registry.configs."${insecure_registry}".tls]
      insecure_skip_verify = true
%{ endif ~}
%{ if try(dockerhub_mirror_endpoint, "") != "" ~}
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["${dockerhub_mirror_endpoint}"]
%{ endif ~}
%{ if try(dockerhub_username, "") != "" && try(dockerhub_password, "") != "" ~}
    [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".auth]
      username = "${dockerhub_username}"
      password = "${dockerhub_password}"
%{ endif ~}
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

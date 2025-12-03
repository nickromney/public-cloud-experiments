terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.6"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

locals {
  kind_workers              = range(var.worker_count)
  kubeconfig_path_expanded  = abspath(pathexpand(var.kubeconfig_path))
  repo_root                 = abspath("${path.module}/../../../..")
  subnet_calculator_root    = "${local.repo_root}/subnet-calculator"
  gitea_known_hosts         = abspath("${path.module}/.run/gitea_known_hosts")
  gitea_known_hosts_cluster = abspath("${path.module}/.run/gitea_known_hosts_cluster")
  gitea_repo_key_path       = abspath("${path.module}/.run/gitea-repo.id_ed25519")
  azure_auth_repo_key_path  = abspath("${path.module}/.run/azure-auth-repo.id_ed25519")
  gitea_http_host           = var.use_external_gitea ? var.gitea_http_host : "127.0.0.1"
  gitea_http_host_local     = var.use_external_gitea ? var.gitea_http_host_local : "127.0.0.1"
  gitea_http_port           = var.use_external_gitea ? var.gitea_http_port : var.gitea_http_node_port
  gitea_http_scheme         = var.gitea_http_scheme
  gitea_curl_insecure       = var.gitea_http_scheme == "https" ? "-k" : ""
  gitea_ssh_host            = var.use_external_gitea ? var.gitea_ssh_host : "127.0.0.1"
  gitea_ssh_host_local      = var.use_external_gitea ? var.gitea_ssh_host_local : "127.0.0.1"
  gitea_ssh_port            = var.use_external_gitea ? var.gitea_ssh_port : var.gitea_ssh_node_port
  gitea_registry_host       = var.gitea_registry_host
  policy_files              = fileset("${path.module}/policies", "**")
  apps_files_all            = fileset("${path.module}/apps", "**")
  apps_skip_prefixes = concat(
    var.enable_azure_auth_sim ? [] : ["azure-auth-sim", "azure-auth-sim.yaml"],
    var.enable_actions_runner ? [] : ["gitea-actions-runner.yaml"]
  )
  apps_files = [
    for file in local.apps_files_all : file
    if length([
      for prefix in local.apps_skip_prefixes : prefix
      if file == prefix || startswith(file, "${prefix}/")
    ]) == 0
  ]
  azure_auth_repo_dirs = [
    "api-apim-simulator",
    "api-fastapi-azure-function",
    "frontend-react",
    "shared-frontend",
  ]
  azure_auth_source_files = flatten([
    for dir in local.azure_auth_repo_dirs : [
      for file in fileset("${local.subnet_calculator_root}/${dir}", "**") : "${dir}/${file}"
    ]
  ])
  azure_auth_workflow_files = concat(
    tolist(fileset("${path.module}/gitea-repos/azure-auth-sim", "**")),
    [for file in fileset("${path.module}/gitea-repos/azure-auth-sim/.gitea", "**") : ".gitea/${file}"]
  )
  repo_checksum = sha256(join("", concat(
    [for file in local.policy_files : filesha256("${path.module}/policies/${file}")],
    [for file in local.apps_files : filesha256("${path.module}/apps/${file}")]
  )))
  azure_auth_repo_checksum = sha256(join("", concat(
    [for file in local.azure_auth_source_files : filesha256("${local.subnet_calculator_root}/${file}")],
    [for file in local.azure_auth_workflow_files : filesha256("${path.module}/gitea-repos/azure-auth-sim/${file}")]
  )))
  extra_port_mappings = concat([
    {
      name           = "argocd"
      container_port = var.argocd_server_node_port
      host_port      = var.argocd_server_node_port
      protocol       = "TCP"
    },
    {
      name           = "hubble-ui"
      container_port = var.hubble_ui_node_port
      host_port      = var.hubble_ui_node_port
      protocol       = "TCP"
    },
    ], var.use_external_gitea ? [] : [
    {
      name           = "gitea-http"
      container_port = var.gitea_http_node_port
      host_port      = var.gitea_http_node_port
      protocol       = "TCP"
    },
    {
      name           = "gitea-ssh"
      container_port = var.gitea_ssh_node_port
      host_port      = var.gitea_ssh_node_port
      protocol       = "TCP"
    }
    ], var.enable_azure_auth_ports ? [
    {
      name           = "azure-auth-sim-oauth2-proxy"
      container_port = var.azure_auth_oauth2_proxy_node_port
      host_port      = var.azure_auth_oauth2_proxy_host_port
      protocol       = "TCP"
    },
    {
      name           = "azure-auth-sim-apim"
      container_port = var.azure_auth_apim_node_port
      host_port      = var.azure_auth_apim_host_port
      protocol       = "TCP"
    },
    {
      name           = "azure-auth-sim-api"
      container_port = var.azure_auth_api_node_port
      host_port      = var.azure_auth_api_host_port
      protocol       = "TCP"
    },
    {
      name           = "azure-auth-sim-keycloak"
      container_port = var.azure_auth_keycloak_node_port
      host_port      = var.azure_auth_keycloak_host_port
      protocol       = "TCP"
    },
  ] : [])

  argocd_values = {
    controller = {
      replicas = 1
    }
    server = {
      service = {
        type     = "NodePort"
        nodePort = var.argocd_server_node_port
      }
    }
    repoServer = {
      extraEnv = [
        {
          name  = "ARGOCD_GIT_MODULES_ENABLED"
          value = "false"
        }
      ]
    }
    redis-ha = {
      enabled = false
    }
  }

  cilium_values_base = {
    kubeProxyReplacement  = false
    routingMode           = "native"
    autoDirectNodeRoutes  = true
    ipv4NativeRoutingCIDR = "10.244.0.0/16"
    bpf = {
      masquerade = false
    }
    ipam = {
      mode = "kubernetes"
    }
    operator = {
      replicas = 1
    }
  }

  hubble_values = var.enable_hubble ? {
    hubble = {
      enabled = true
      relay = {
        enabled = true
      }
      ui = {
        enabled = true
        service = {
          type     = "NodePort"
          nodePort = var.hubble_ui_node_port
        }
      }
    }
  } : {}

  cilium_values = merge(local.cilium_values_base, local.hubble_values)
}

provider "kubernetes" {
  config_path    = local.kubeconfig_path_expanded
  config_context = length(trimspace(var.kubeconfig_context)) > 0 ? var.kubeconfig_context : null
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path_expanded
    config_context = length(trimspace(var.kubeconfig_context)) > 0 ? var.kubeconfig_context : null
  }
}

provider "kubectl" {
  config_path    = local.kubeconfig_path_expanded
  config_context = length(trimspace(var.kubeconfig_context)) > 0 ? var.kubeconfig_context : null
}

data "http" "external_gitea_health" {
  count = var.use_external_gitea ? 1 : 0

  url = "${var.gitea_http_scheme}://${var.gitea_http_host_local}:${var.gitea_http_port}/api/healthz"

  request_headers = {
    Accept = "application/json"
  }

  # WARNING: insecure=true skips TLS verification. Only use for local dev with self-signed certs.
  # For production, configure proper CA trust and set insecure=false.
  insecure = true

  retry {
    attempts = 3
  }
}

resource "local_file" "kind_config" {
  filename = var.kind_config_path
  content = templatefile("${path.module}/templates/kind-config.yaml.tpl", {
    workers = local.kind_workers
    ports   = local.extra_port_mappings
    extra_mounts = [] # no hostPath mounts by default; keep template inputs satisfied
  })
}

resource "kind_cluster" "local" {
  name            = var.cluster_name
  wait_for_ready  = false # avoid replacements between stages; kubernetes provider connects once API is up
  kubeconfig_path = local.kubeconfig_path_expanded
  node_image      = var.node_image

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      disable_default_cni = true
      kube_proxy_mode     = "iptables"
    }

    node {
      role = "control-plane"

      dynamic "extra_port_mappings" {
        for_each = local.extra_port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          protocol       = try(extra_port_mappings.value.protocol, "TCP")
        }
      }
    }

    dynamic "node" {
      for_each = local.kind_workers
      content {
        role = "worker"
      }
    }
  }
}

resource "local_sensitive_file" "kubeconfig" {
  content              = kind_cluster.local.kubeconfig
  filename             = local.kubeconfig_path_expanded
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [kind_cluster.local]
}

resource "kubernetes_namespace" "gitea" {
  count = var.enable_namespaces && !var.use_external_gitea ? 1 : 0

  metadata {
    name = "gitea"
    labels = {
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_namespace" "cilium_team_a" {
  count = var.enable_namespaces ? 1 : 0

  metadata {
    name = "cilium-team-a"
    labels = {
      "cilium.io/namespace-isolation" = "true"
      "app.kubernetes.io/managed-by"  = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_namespace" "cilium_team_b" {
  count = var.enable_namespaces ? 1 : 0

  metadata {
    name = "cilium-team-b"
    labels = {
      "cilium.io/namespace-isolation" = "true"
      "app.kubernetes.io/managed-by"  = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_namespace" "kyverno" {
  count = var.enable_namespaces ? 1 : 0

  metadata {
    name = "kyverno"
    labels = {
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_namespace" "kyverno_sandbox" {
  count = var.enable_namespaces ? 1 : 0

  metadata {
    name = "kyverno-sandbox"
    labels = {
      "kyverno.io/isolate"           = "true"
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubectl_manifest" "azure_auth_namespace" {
  count = var.enable_azure_auth_sim ? 1 : 0

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.azure_auth_namespace}
  labels:
    app.kubernetes.io/part-of: azure-auth-sim
    app.kubernetes.io/managed-by: argocd
EOF

  wait              = true
  validate_schema   = false
  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_namespace" "argocd" {
  count = var.enable_namespaces ? 1 : 0


  metadata {
    name = var.argocd_namespace
    labels = {
      app = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "helm_release" "cilium" {
  count = var.enable_cilium ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  values = [yamlencode(local.cilium_values)]

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = false

  values = [yamlencode(local.argocd_values)]

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
    kubernetes_namespace.argocd[0],
    helm_release.cilium[0]
  ]
}

resource "null_resource" "wait_for_gitea" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0


  triggers = {
    gitea_app = sha1(kubectl_manifest.argocd_app_gitea[0].yaml_body)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG=${var.kubeconfig_path}
for i in {1..30}; do
  if kubectl -n gitea get deploy/gitea >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for gitea deployment to be created by Argo CD... (attempt $i)" >&2
  sleep 10
done
kubectl -n gitea rollout status deploy/gitea --timeout=300s
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    helm_release.argocd[0],
    kubectl_manifest.argocd_app_gitea[0]
  ]
}

resource "tls_private_key" "gitea_repo" {
  count = var.enable_gitea ? 1 : 0


  algorithm = "ED25519"
}

resource "tls_private_key" "gitea_repo_azure_auth" {
  count = var.enable_gitea && var.enable_actions_runner ? 1 : 0

  algorithm = "ED25519"
}

resource "null_resource" "gitea_create_repo" {
  count = var.enable_gitea ? 1 : 0


  triggers = {
    rollout = var.use_external_gitea ? "external" : null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
    -H "Content-Type: application/json" \
    -d '{"name":"policies","private":false,"default_branch":"main","auto_init":true,"description":"Policies for Cilium and Kyverno"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/repos)
  if echo "$status" | grep -Eq "200|201|409"; then
    exit 0
  fi
  echo "Gitea repo create returned HTTP $status, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to create policies repo in Gitea" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

}

resource "null_resource" "gitea_create_repo_azure_auth" {
  count = var.enable_gitea && var.enable_actions_runner ? 1 : 0


  triggers = {
    rollout = var.use_external_gitea ? "external" : null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
    -H "Content-Type: application/json" \
    -d '{"name":"azure-auth-sim","private":false,"default_branch":"main","auto_init":true,"description":"Azure auth simulation workloads (API/APIM simulator/frontend)"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/repos)
  if echo "$status" | grep -Eq "200|201|409"; then
    exit 0
  fi
  echo "Gitea azure-auth-sim repo create returned HTTP $status, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to create azure-auth-sim repo in Gitea" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

}

resource "null_resource" "gitea_add_deploy_key" {
  count = var.enable_gitea ? 1 : 0


  triggers = {
    repo    = null_resource.gitea_create_repo[0].id
    ssh_key = tls_private_key.gitea_repo[0].public_key_openssh
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
    -H "Content-Type: application/json" \
    -d '{"title":"argocd-repo-key","key":"${tls_private_key.gitea_repo[0].public_key_openssh}","read_only":false}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/policies/keys)
  if echo "$status" | grep -Eq "200|201|409|422"; then
    exit 0
  fi
  echo "Gitea deploy key add returned HTTP $status, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to add deploy key to Gitea repo" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_create_repo[0],
    tls_private_key.gitea_repo[0]
  ]
}

resource "null_resource" "gitea_add_deploy_key_azure_auth" {
  count = var.enable_gitea && var.enable_actions_runner ? 1 : 0


  triggers = {
    repo    = null_resource.gitea_create_repo_azure_auth[0].id
    ssh_key = tls_private_key.gitea_repo_azure_auth[0].public_key_openssh
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
    -H "Content-Type: application/json" \
    -d '{"title":"azure-auth-repo-key","key":"${tls_private_key.gitea_repo_azure_auth[0].public_key_openssh}","read_only":false}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/azure-auth-sim/keys)
  if echo "$status" | grep -Eq "200|201|409|422"; then
    exit 0
  fi
  echo "Gitea deploy key add (azure-auth-sim) returned HTTP $status, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to add deploy key to azure-auth-sim repo" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_create_repo_azure_auth[0],
    tls_private_key.gitea_repo_azure_auth[0]
  ]
}

# Local known_hosts for git operations from host machine (127.0.0.1:30022)
resource "null_resource" "gitea_known_hosts" {
  count = var.enable_gitea ? 1 : 0

  triggers = {
    gitea_repo = null_resource.gitea_create_repo[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
mkdir -p "${path.module}/.run"
for i in {1..20}; do
  if ssh-keyscan -p ${local.gitea_ssh_port} ${local.gitea_ssh_host_local} > "${local.gitea_known_hosts}"; then
    exit 0
  fi
  echo "ssh-keyscan failed, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to capture Gitea SSH host key" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [null_resource.gitea_create_repo[0]]
}

# Cluster-internal known_hosts for ArgoCD (gitea-ssh.gitea.svc.cluster.local:22)
resource "null_resource" "gitea_known_hosts_cluster" {
  count = var.enable_gitea ? 1 : 0

  triggers = {
    gitea_repo = null_resource.gitea_create_repo[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
mkdir -p "${path.module}/.run"
for i in {1..20}; do
  if kubectl run ssh-keyscan-$$ --image=alpine:latest --rm -i --restart=Never -q -- \
    sh -c "apk add --no-cache openssh-client >/dev/null 2>&1 && ssh-keyscan -p ${local.gitea_ssh_port} ${local.gitea_ssh_host} 2>/dev/null" \
    > "${local.gitea_known_hosts_cluster}" 2>/dev/null && [ -s "${local.gitea_known_hosts_cluster}" ]; then
    exit 0
  fi
  echo "ssh-keyscan (cluster) failed, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to capture Gitea SSH host key (cluster)" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [null_resource.gitea_create_repo[0]]
}

data "local_file" "gitea_known_hosts" {
  count      = var.enable_gitea ? 1 : 0
  filename   = local.gitea_known_hosts
  depends_on = [null_resource.gitea_known_hosts[0]]
}

data "local_file" "gitea_known_hosts_cluster" {
  count      = var.enable_gitea ? 1 : 0
  filename   = local.gitea_known_hosts_cluster
  depends_on = [null_resource.gitea_known_hosts_cluster[0]]
}

# Add Gitea SSH host key to ArgoCD's global known_hosts configmap
resource "null_resource" "argocd_add_gitea_known_host" {
  count = var.enable_gitea ? 1 : 0

  triggers = {
    gitea_host_key = md5(data.local_file.gitea_known_hosts_cluster[0].content)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG=${var.kubeconfig_path}

# Get current known_hosts from configmap
kubectl get configmap argocd-ssh-known-hosts-cm -n ${var.argocd_namespace} \
  -o jsonpath='{.data.ssh_known_hosts}' > /tmp/argocd-known-hosts.txt

# Extract any non-comment key line (supports ssh-rsa, ssh-ed25519, ecdsa, etc.)
GITEA_KEY=$(grep -E "^[^#]" "${local.gitea_known_hosts_cluster}" | grep "${local.gitea_ssh_host}" | head -1)

# Check if already present
if ! grep -q "${local.gitea_ssh_host}" /tmp/argocd-known-hosts.txt; then
  echo "$GITEA_KEY" >> /tmp/argocd-known-hosts.txt
  kubectl create configmap argocd-ssh-known-hosts-cm -n ${var.argocd_namespace} \
    --from-file=ssh_known_hosts=/tmp/argocd-known-hosts.txt \
    --dry-run=client -o yaml | kubectl apply -f -
  # Restart repo-server to pick up new known hosts
  kubectl rollout restart deployment argocd-repo-server -n ${var.argocd_namespace}
  kubectl rollout status deployment argocd-repo-server -n ${var.argocd_namespace} --timeout=60s
fi
rm -f /tmp/argocd-known-hosts.txt
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    helm_release.argocd[0],
    null_resource.gitea_known_hosts_cluster[0],
    data.local_file.gitea_known_hosts_cluster[0]
  ]
}


resource "local_sensitive_file" "gitea_repo_private_key" {
  count = var.enable_gitea ? 1 : 0


  content              = tls_private_key.gitea_repo[0].private_key_openssh
  filename             = local.gitea_repo_key_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_sensitive_file" "gitea_azure_auth_repo_private_key" {
  count = var.enable_gitea && var.enable_actions_runner ? 1 : 0

  content              = tls_private_key.gitea_repo_azure_auth[0].private_key_openssh
  filename             = local.azure_auth_repo_key_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "null_resource" "seed_gitea_repo" {
  count = var.enable_gitea ? 1 : 0


  triggers = {
    repo_id    = null_resource.gitea_create_repo[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.repo_checksum
  }

  provisioner "local-exec" {
    environment = {
      GIT_SSH_COMMAND = "ssh -i ${local.gitea_repo_key_path} -o UserKnownHostsFile=${local.gitea_known_hosts} -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes"
    }
    command     = <<EOT
set -euo pipefail
if [ "${var.use_external_gitea}" = "true" ]; then
  echo "External Gitea detected; skipping Terraform seeding (stage scripts handle this)." >&2
  exit 0
fi
TMP_DIR=$(mktemp -d)
cp -r ${path.module}/apps "$TMP_DIR"/
if [ "${var.enable_azure_auth_sim}" != "true" ]; then
  rm -rf "$TMP_DIR/apps/azure-auth-sim" "$TMP_DIR/apps/azure-auth-sim.yaml"
fi
if [ "${var.enable_actions_runner}" != "true" ]; then
  rm -f "$TMP_DIR/apps/gitea-actions-runner.yaml"
fi
cp -r ${path.module}/policies "$TMP_DIR"/
cd "$TMP_DIR"
git init -q
git config user.email "argocd@gitea.local"
git config user.name "argocd"
git config commit.gpgsign false
git add .
git commit -q -m "Seed policies"
git branch -M main
git remote add origin ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host_local}:${local.gitea_ssh_port}/${var.gitea_admin_username}/policies.git
git push -f origin main
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_add_deploy_key[0],
    null_resource.gitea_known_hosts[0],
    data.local_file.gitea_known_hosts[0],
    local_sensitive_file.gitea_repo_private_key[0]
  ]
}

resource "null_resource" "seed_gitea_repo_azure_auth" {
  count = var.enable_gitea && var.enable_actions_runner ? 1 : 0


  triggers = {
    repo_id    = null_resource.gitea_create_repo_azure_auth[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.azure_auth_repo_checksum
  }

  provisioner "local-exec" {
    environment = {
      GIT_SSH_COMMAND = "ssh -i ${local.azure_auth_repo_key_path} -o UserKnownHostsFile=${local.gitea_known_hosts} -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes"
    }
    command     = <<EOT
set -euo pipefail
if [ "${var.use_external_gitea}" = "true" ]; then
  echo "External Gitea detected; skipping Terraform seeding (stage scripts handle this)." >&2
  exit 0
fi
TMP_DIR=$(mktemp -d)
cp -r ${path.module}/gitea-repos/azure-auth-sim/. "$TMP_DIR"/
for dir in ${join(" ", local.azure_auth_repo_dirs)}; do
  cp -r "${local.subnet_calculator_root}/$${dir}" "$TMP_DIR"/
done
cd "$TMP_DIR"
git init -q
git config user.email "argocd@gitea.local"
git config user.name "argocd"
git config commit.gpgsign false
git add .
git commit -q -m "Seed azure-auth-sim sources"
git branch -M main
git remote add origin ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host_local}:${local.gitea_ssh_port}/${var.gitea_admin_username}/azure-auth-sim.git
git push -f origin main
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_add_deploy_key_azure_auth[0],
    null_resource.gitea_known_hosts[0],
    data.local_file.gitea_known_hosts[0],
    local_sensitive_file.gitea_azure_auth_repo_private_key[0]
  ]
}

resource "null_resource" "gitea_azure_auth_repo_secrets" {
  count = var.enable_gitea && var.enable_actions_runner ? 1 : 0


  triggers = {
    repo_id  = null_resource.gitea_create_repo_azure_auth[0].id
    password = md5(var.gitea_admin_password)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
create_secret() {
  local name="$1"
  local value="$2"
  for i in {1..5}; do
    status=$(curl ${local.gitea_curl_insecure} -s -o /dev/null -w "%%{http_code}" -X PUT \
      -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":\"$${value}\"}" \
      ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/azure-auth-sim/actions/secrets/$${name})
    if echo "$status" | grep -Eq "200|201|204"; then
      return 0
    fi
    echo "Setting secret $${name} returned HTTP $status, retrying... ($i/5)" >&2
    sleep 3
  done
  echo "Failed to create/update secret $${name}" >&2
  exit 1
}

create_secret "REGISTRY_USERNAME" "${var.gitea_admin_username}"
create_secret "REGISTRY_PASSWORD" "${var.gitea_admin_password}"
create_secret "REGISTRY_HOST" "${local.gitea_registry_host}"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_create_repo_azure_auth[0]
  ]
}

resource "kubernetes_secret" "argocd_repo_gitea" {
  count = var.enable_gitea ? 1 : 0


  metadata {
    name      = "repo-gitea-policies"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = "ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host}:${local.gitea_ssh_port}/${var.gitea_admin_username}/policies.git"
    sshPrivateKey = tls_private_key.gitea_repo[0].private_key_openssh
    sshKnownHosts = data.local_file.gitea_known_hosts_cluster[0].content
    insecure      = "false"
  }

  lifecycle {
    precondition {
      condition     = !var.use_external_gitea || (length(data.http.external_gitea_health) > 0 && data.http.external_gitea_health[0].status_code == 200)
      error_message = "External Gitea is not reachable at ${var.gitea_http_scheme}://${var.gitea_http_host_local}:${var.gitea_http_port}. Start it before applying."
    }
  }

  depends_on = [
    null_resource.gitea_add_deploy_key[0],
    null_resource.gitea_known_hosts_cluster[0],
    data.local_file.gitea_known_hosts_cluster[0],
    null_resource.seed_gitea_repo[0],
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_secret" "azure_auth_registry_credentials" {
  count = var.enable_azure_auth_sim ? 1 : 0


  metadata {
    name      = "gitea-registry-creds"
    namespace = var.azure_auth_namespace
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.gitea_registry_host) = {
          username = var.gitea_admin_username
          password = var.gitea_admin_password
          auth     = base64encode("${var.gitea_admin_username}:${var.gitea_admin_password}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [
    kubectl_manifest.azure_auth_namespace[0]
  ]
}

resource "tls_private_key" "argocd_repo" {
  count = var.generate_repo_ssh_key ? 1 : 0

  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  count      = var.generate_repo_ssh_key ? 1 : 0
  content    = tls_private_key.argocd_repo[0].private_key_pem
  filename   = var.ssh_private_key_path
  depends_on = [tls_private_key.argocd_repo[0]]
}

resource "local_file" "ssh_public_key" {
  count    = var.generate_repo_ssh_key ? 1 : 0
  content  = tls_private_key.argocd_repo[0].public_key_openssh
  filename = var.ssh_public_key_path
}

resource "kubectl_manifest" "argocd_app_gitea" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0

  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitea
  namespace: ${var.argocd_namespace}
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace.gitea[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: https://dl.gitea.io/charts/
    chart: gitea
    targetRevision: ${var.gitea_chart_version}
    helm:
      releaseName: gitea
      values: |
        service:
          http:
            type: NodePort
            nodePort: ${var.gitea_http_node_port}
          ssh:
            type: NodePort
            nodePort: ${var.gitea_ssh_node_port}
        ingress:
          enabled: false
        postgresql:
          enabled: true
        postgresql-ha:
          enabled: false
        gitea:
          admin:
            username: ${var.gitea_admin_username}
            password: ${var.gitea_admin_password}
            email: "admin@gitea.local"
          config:
            server:
              DISABLE_SSH: false
              SSH_PORT: ${var.gitea_ssh_node_port}
              ROOT_URL: http://127.0.0.1:${var.gitea_http_node_port}/
            packages:
              ENABLED: true
              ALLOWED_TYPES: "*"
            actions:
              ENABLED: true
            security:
              INSTALL_LOCK: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd[0],
    kubernetes_namespace.gitea[0]
  ]
}

# App of Apps - root application that manages all child applications
# Child apps are defined in apps/ and synced from Gitea
resource "kubectl_manifest" "argocd_app_of_apps" {
  count = var.enable_gitea && (var.enable_policies || var.enable_azure_auth_sim) ? 1 : 0

  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${var.argocd_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host}:${local.gitea_ssh_port}/${var.gitea_admin_username}/policies.git
    targetRevision: main
    path: apps
    directory:
      recurse: false
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
EOF

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd[0],
    kubernetes_namespace.kyverno[0],
    kubernetes_namespace.kyverno_sandbox[0],
    kubernetes_namespace.cilium_team_a[0],
    kubernetes_namespace.cilium_team_b[0],
    kubernetes_secret.argocd_repo_gitea[0],
    null_resource.seed_gitea_repo[0],
    null_resource.argocd_add_gitea_known_host[0]
  ]
}

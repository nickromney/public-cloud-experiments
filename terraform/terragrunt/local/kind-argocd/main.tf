terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = "kind-${var.cluster_name}"
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = "kind-${var.cluster_name}"
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = "kind-${var.cluster_name}"
}

locals {
  kind_workers        = range(var.worker_count)
  gitea_known_hosts   = "${path.module}/.run/gitea_known_hosts"
  gitea_repo_key_path = "${path.module}/.run/gitea-repo.id_ed25519"
  policy_files        = fileset("${path.module}/policies", "**")
  policies_checksum = sha256(join("", [
    for file in local.policy_files : filesha256("${path.module}/policies/${file}")
  ]))
  extra_port_mappings = [
    {
      name           = "argocd"
      container_port = var.argocd_server_node_port
      host_port      = var.argocd_server_node_port
      protocol       = "TCP"
    },
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
    },
    {
      name           = "hubble-ui"
      container_port = var.hubble_ui_node_port
      host_port      = var.hubble_ui_node_port
      protocol       = "TCP"
    },
  ]

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

resource "local_file" "kind_config" {
  filename = var.kind_config_path
  content = templatefile("${path.module}/templates/kind-config.yaml.tpl", {
    workers = local.kind_workers
    ports   = local.extra_port_mappings
  })
}

resource "kind_cluster" "local" {
  name            = var.cluster_name
  wait_for_ready  = true
  kubeconfig_path = var.kubeconfig_path
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
  filename             = var.kubeconfig_path
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [kind_cluster.local]
}

resource "kubernetes_namespace" "gitea" {
  count = var.enable_namespaces ? 1 : 0

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
  count = var.enable_gitea ? 1 : 0


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

resource "null_resource" "gitea_create_repo" {
  count = var.enable_gitea ? 1 : 0


  triggers = {
    rollout = null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl -s -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
    -H "Content-Type: application/json" \
    -d '{"name":"policies","private":false,"default_branch":"main","auto_init":true,"description":"Policies for Cilium and Kyverno"}' \
    http://127.0.0.1:${var.gitea_http_node_port}/api/v1/user/repos)
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

  depends_on = [null_resource.wait_for_gitea[0]]
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
  status=$(curl -s -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_password}" \
    -H "Content-Type: application/json" \
    -d '{"title":"argocd-repo-key","key":"${tls_private_key.gitea_repo[0].public_key_openssh}","read_only":false}' \
    http://127.0.0.1:${var.gitea_http_node_port}/api/v1/repos/${var.gitea_admin_username}/policies/keys)
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
  if ssh-keyscan -p ${var.gitea_ssh_node_port} 127.0.0.1 > "${local.gitea_known_hosts}"; then
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

data "local_file" "gitea_known_hosts" {
  count      = var.enable_gitea ? 1 : 0
  filename   = local.gitea_known_hosts
  depends_on = [null_resource.gitea_known_hosts[0]]
}

resource "local_sensitive_file" "gitea_repo_private_key" {
  count = var.enable_gitea ? 1 : 0


  content              = tls_private_key.gitea_repo[0].private_key_pem
  filename             = local.gitea_repo_key_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "null_resource" "seed_gitea_repo" {
  count = var.enable_gitea ? 1 : 0


  triggers = {
    repo_id    = null_resource.gitea_create_repo[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.policies_checksum
  }

  provisioner "local-exec" {
    environment = {
      GIT_SSH_COMMAND = "ssh -i ${local.gitea_repo_key_path} -o UserKnownHostsFile=${local.gitea_known_hosts} -o StrictHostKeyChecking=yes"
    }
    command     = <<EOT
set -euo pipefail
TMP_DIR=$(mktemp -d)
cp -r ${path.module}/policies/* "$TMP_DIR"/
cd "$TMP_DIR"
git init -q
git config user.email "argocd@gitea.local"
git config user.name "argocd"
git add .
git commit -q -m "Seed policies"
git branch -M main
git remote add origin ssh://git@127.0.0.1:${var.gitea_ssh_node_port}/${var.gitea_admin_username}/policies.git
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

resource "kubernetes_secret" "argocd_repo_gitea" {
  count = var.enable_gitea ? 1 : 0


  metadata {
    name      = "repo-gitea-policies"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repo"
    }
  }

  data = {
    url           = "ssh://git@127.0.0.1:${var.gitea_ssh_node_port}/${var.gitea_admin_username}/policies.git"
    sshPrivateKey = tls_private_key.gitea_repo[0].private_key_pem
    sshKnownHosts = data.local_file.gitea_known_hosts[0].content
    insecure      = "false"
  }

  depends_on = [
    null_resource.gitea_add_deploy_key[0],
    null_resource.gitea_known_hosts[0],
    data.local_file.gitea_known_hosts[0],
    null_resource.seed_gitea_repo[0],
    local_sensitive_file.kubeconfig
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
  count = var.enable_gitea ? 1 : 0

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

resource "kubectl_manifest" "argocd_app_cilium_policies" {
  count = var.enable_policies ? 1 : 0


  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cilium-policies
  namespace: ${var.argocd_namespace}
spec:
  project: default
  destination:
    namespace: ${var.argocd_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://git@127.0.0.1:${var.gitea_ssh_node_port}/${var.gitea_admin_username}/policies.git
    targetRevision: main
    path: cilium
    directory:
      recurse: true
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
    kubernetes_namespace.cilium_team_a[0],
    kubernetes_namespace.cilium_team_b[0]
  ]
}

resource "kubectl_manifest" "argocd_app_kyverno" {
  count = var.enable_policies ? 1 : 0


  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno
  namespace: ${var.argocd_namespace}
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace.kyverno[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: https://kyverno.github.io/kyverno/
    chart: kyverno
    targetRevision: 3.2.7
    helm:
      releaseName: kyverno
      values: |
        crds:
          install: true
        admissionController:
          replicas: 1
        backgroundController:
          replicas: 1
        cleanupController:
          replicas: 1
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
    kubernetes_namespace.kyverno[0]
  ]
}

resource "kubectl_manifest" "argocd_app_kyverno_policies" {
  count = var.enable_policies ? 1 : 0


  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno-policies
  namespace: ${var.argocd_namespace}
spec:
  project: default
  destination:
    namespace: ${var.argocd_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://git@127.0.0.1:${var.gitea_ssh_node_port}/${var.gitea_admin_username}/policies.git
    targetRevision: main
    path: kyverno
    directory:
      recurse: true
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
    kubernetes_namespace.kyverno_sandbox[0]
  ]
}

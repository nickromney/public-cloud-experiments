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
  external_ssh_key_path     = abspath(var.ssh_private_key_path)
  gitea_http_host           = var.use_external_gitea ? var.gitea_http_host : "127.0.0.1"
  gitea_http_host_local     = var.use_external_gitea ? var.gitea_http_host_local : "127.0.0.1"
  gitea_http_port           = var.use_external_gitea ? var.gitea_http_port : var.gitea_http_node_port
  gitea_http_scheme         = var.gitea_http_scheme
  gitea_curl_insecure       = var.gitea_http_scheme == "https" ? "-k" : ""
  gitea_ssh_host            = var.use_external_gitea ? var.gitea_ssh_host : "127.0.0.1"
  gitea_ssh_host_local      = var.use_external_gitea ? var.gitea_ssh_host_local : "127.0.0.1"
  gitea_ssh_port            = var.use_external_gitea ? var.gitea_ssh_port : var.gitea_ssh_node_port
  # Cluster-internal access (for pods inside Kubernetes, e.g., ArgoCD, kubectl run ssh-keyscan)
  gitea_ssh_host_cluster  = var.use_external_gitea ? var.gitea_ssh_host : var.gitea_ssh_host_cluster
  gitea_ssh_port_cluster  = var.use_external_gitea ? var.gitea_ssh_port : var.gitea_ssh_port_cluster
  gitea_http_host_cluster = var.use_external_gitea ? var.gitea_http_host : var.gitea_http_host_cluster
  gitea_http_port_cluster = var.use_external_gitea ? var.gitea_http_port : var.gitea_http_port_cluster
  gitea_registry_host     = var.gitea_registry_host
  cluster_policy_files    = fileset("${path.module}/cluster-policies", "**")
  apps_files_all          = fileset("${path.module}/apps", "**")
  apps_skip_prefixes = concat(
    # Skip azure-auth-sim apps if not enabled
    var.enable_azure_auth_sim ? [] : ["azure-auth-sim", "azure-auth-sim.yaml", "azure-auth-sim-internal.yaml"],
    # For external Gitea, skip internal variant; for in-cluster, skip external variant
    var.enable_azure_auth_sim && var.use_external_gitea ? ["azure-auth-sim-internal.yaml"] : [],
    var.enable_azure_auth_sim && !var.use_external_gitea ? ["azure-auth-sim.yaml"] : [],
    # Skip runner for external Gitea (uses host runner via external build process) or if not enabled
    !var.enable_actions_runner || var.use_external_gitea ? ["gitea-actions-runner.yaml", "gitea-actions-runner"] : [],
    # Observability stacks can overload kind control plane; keep optional.
    var.enable_victoria_metrics ? [] : ["_applications/victoria-metrics.yaml"],
    var.enable_signoz ? [] : ["_applications/signoz.yaml"]
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
    [for file in local.cluster_policy_files : filesha256("${path.module}/cluster-policies/${file}")],
    [for file in local.apps_files : filesha256("${path.module}/apps/${file}")]
  )))
  azure_auth_repo_checksum = sha256(join("", concat(
    [for file in local.azure_auth_source_files : filesha256("${local.subnet_calculator_root}/${file}")],
    [for file in local.azure_auth_workflow_files : filesha256("${path.module}/gitea-repos/azure-auth-sim/${file}")]
  )))

  sentiment_auth_ui_root = "${local.repo_root}/sentiment-llm/frontend-react-vite/sentiment-auth-ui"
  sentiment_auth_repo_files = concat(
    tolist(fileset(local.sentiment_auth_ui_root, "**")),
    [for file in fileset("${local.sentiment_auth_ui_root}/.gitea", "**") : ".gitea/${file}"]
  )
  sentiment_auth_repo_checksum = sha256(join("", [
    for file in local.sentiment_auth_repo_files : filesha256("${local.sentiment_auth_ui_root}/${file}")
  ]))

  sentiment_api_root = "${local.repo_root}/sentiment-llm/api-sentiment"
  sentiment_api_repo_files = concat(
    [
      for file in fileset(local.sentiment_api_root, "**") : file
      if !startswith(file, "node_modules/") && file != "node_modules"
    ],
    [for file in fileset("${local.sentiment_api_root}/.gitea", "**") : ".gitea/${file}"]
  )
  sentiment_api_repo_checksum = sha256(join("", [
    for file in local.sentiment_api_repo_files : filesha256("${local.sentiment_api_root}/${file}")
  ]))
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
    {
      name           = "signoz-ui"
      container_port = var.signoz_ui_node_port
      host_port      = var.signoz_ui_host_port
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
      name           = "azure-auth-https"
      container_port = var.azure_auth_gateway_node_port
      host_port      = var.azure_auth_gateway_host_port
      protocol       = "TCP"
    },
  ] : [])

  argocd_values = {
    configs = merge(
      {
        cm = merge(
          {
            url = "https://argocd.127.0.0.1.sslip.io"
          },
          var.enable_platform_sso ? {
            "oidc.config"                   = <<-EOT
              name: Keycloak
              issuer: https://${var.platform_sso_keycloak_host}/realms/subnet-calculator
              clientID: ${var.argocd_oidc_client_id}
              clientSecret: $oidc.keycloak.clientSecret
              requestedScopes:
                - openid
                - profile
                - email
            EOT
            "oidc.tls.insecure.skip.verify" = "true"
          } : {}
        )
        params = {
          "server.insecure" = true
        }
        rbac = {
          "policy.csv"       = ""
          "policy.default"   = "role:admin"
          "policy.matchMode" = "glob"
          "scopes"           = "[groups]"
        }
      },
      var.enable_platform_sso ? {
        secret = {
          extra = {
            "oidc.keycloak.clientSecret" = var.argocd_oidc_client_secret
          }
        }
      } : {}
    )
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
    cluster = {
      name = var.cluster_name
      id   = 0
    }
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

    # Expose cilium-agent Prometheus metrics (needed to scrape Cilium auth/mesh metrics into SigNoz).
    prometheus = {
      enabled = true
    }

    # Mutual authentication (mTLS identity) + optional WireGuard encryption.
    # WireGuard has proven flaky on kind (node-specific DNS/service timeouts), so keep it disabled by default.
    encryption = {
      enabled        = var.cilium_enable_wireguard
      type           = "wireguard"
      nodeEncryption = true
    }

    authentication = {
      enabled = var.enable_cilium_mesh_auth
      mutual = {
        spire = {
          enabled = var.enable_cilium_mesh_auth
          install = {
            enabled = var.enable_cilium_mesh_auth
            server = {
              securityContext = {
                runAsUser  = 0
                runAsGroup = 0
              }
            }
            agent = {
              securityContext = {
                runAsUser  = 0
                runAsGroup = 0
              }
            }
          }
        }
      }
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

  # Template variables for generated app YAML files
  # All cluster-internal addressing is configured here from tfvars
  app_template_vars = {
    gitea_ssh_username               = var.gitea_ssh_username
    gitea_ssh_host                   = local.gitea_ssh_host_cluster
    gitea_ssh_port                   = local.gitea_ssh_port_cluster
    gitea_admin_username             = var.gitea_admin_username
    registry_host                    = var.gitea_registry_host
    argocd_namespace                 = var.argocd_namespace
    azure_auth_gateway_node_port     = var.azure_auth_gateway_node_port
    azure_auth_gateway_node_port_uat = var.azure_auth_gateway_node_port_uat
    # Multi-namespace architecture namespaces
    azure_auth_namespaces        = var.azure_auth_namespaces
    azure_auth_gateway_namespace = var.azure_auth_gateway_namespace
    azure_entraid_namespace      = var.azure_entraid_namespace
    azure_apim_namespace         = var.azure_apim_namespace
  }

  # Staging directory for generated app files
  generated_apps_dir = "${path.module}/.run/generated-apps"
}

# -----------------------------------------------------------------------------
# Generated App YAML Files (templated with correct URLs from tfvars)
# -----------------------------------------------------------------------------

resource "local_file" "app_azure_auth_sim_dev" {
  count    = var.enable_azure_auth_sim && var.enable_subnetcalc_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/azure-auth-sim-dev.yaml"
  content = templatefile("${path.module}/templates/apps/azure-auth-sim.yaml.tpl", merge(local.app_template_vars, {
    env_name             = "dev"
    azure_auth_namespace = lookup(var.azure_auth_namespaces, "dev", "dev")
  }))
}

resource "local_file" "app_azure_auth_sim_uat" {
  count    = var.enable_azure_auth_sim && var.enable_subnetcalc_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/azure-auth-sim-uat.yaml"
  content = templatefile("${path.module}/templates/apps/azure-auth-sim.yaml.tpl", merge(local.app_template_vars, {
    env_name             = "uat"
    azure_auth_namespace = lookup(var.azure_auth_namespaces, "uat", "uat")
  }))
}

resource "local_file" "app_azure_auth_gateway" {
  count    = var.enable_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/azure-auth-gateway.yaml"
  content  = templatefile("${path.module}/templates/apps/azure-auth-gateway.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_azure_entraid_sim" {
  count    = var.enable_azure_auth_sim && var.enable_azure_entraid_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/azure-entraid-sim.yaml"
  content  = templatefile("${path.module}/templates/apps/azure-entraid-sim.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_azure_apim_sim" {
  count    = var.enable_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/azure-apim-sim.yaml"
  content  = templatefile("${path.module}/templates/apps/azure-apim-sim.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_kyverno" {
  count    = var.enable_policies ? 1 : 0
  filename = "${local.generated_apps_dir}/kyverno.yaml"
  content  = templatefile("${path.module}/templates/apps/kyverno.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_signoz_k8s_infra" {
  count    = var.enable_signoz_k8s_infra ? 1 : 0
  filename = "${local.generated_apps_dir}/signoz-k8s-infra.yaml"
  content = templatefile("${path.module}/templates/apps/signoz-k8s-infra.yaml.tpl", merge(local.app_template_vars, {
    cluster_name = var.cluster_name
  }))
}

resource "local_file" "app_cilium_policies" {
  filename = "${local.generated_apps_dir}/cilium-policies.yaml"
  content  = templatefile("${path.module}/templates/apps/cilium-policies.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_kyverno_policies" {
  filename = "${local.generated_apps_dir}/kyverno-policies.yaml"
  content  = templatefile("${path.module}/templates/apps/kyverno-policies.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_gitea_actions_runner" {
  count    = var.enable_actions_runner && !var.use_external_gitea ? 1 : 0
  filename = "${local.generated_apps_dir}/gitea-actions-runner.yaml"
  content  = templatefile("${path.module}/templates/apps/gitea-actions-runner.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_nginx_gateway_fabric" {
  count    = var.enable_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/nginx-gateway-fabric.yaml"
  content  = templatefile("${path.module}/templates/apps/nginx-gateway-fabric.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_platform_gateway_routes" {
  count    = var.enable_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/platform-gateway-routes.yaml"
  content  = templatefile("${path.module}/templates/apps/platform-gateway-routes.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_sentiment_core" {
  count    = var.enable_llm_sentiment ? 1 : 0
  filename = "${local.generated_apps_dir}/sentiment-core.yaml"
  content  = templatefile("${path.module}/templates/apps/sentiment-core.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_sentiment_dev" {
  count    = var.enable_llm_sentiment ? 1 : 0
  filename = "${local.generated_apps_dir}/sentiment-dev.yaml"
  content  = templatefile("${path.module}/templates/apps/sentiment-dev.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_sentiment_uat" {
  count    = var.enable_llm_sentiment ? 1 : 0
  filename = "${local.generated_apps_dir}/sentiment-uat.yaml"
  content  = templatefile("${path.module}/templates/apps/sentiment-uat.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_sentiment_auth_dev" {
  count    = var.enable_sentiment_auth_frontend ? 1 : 0
  filename = "${local.generated_apps_dir}/sentiment-auth-dev.yaml"
  content  = templatefile("${path.module}/templates/apps/sentiment-auth-dev.yaml.tpl", local.app_template_vars)
}

resource "local_file" "app_sentiment_auth_uat" {
  count    = var.enable_sentiment_auth_frontend ? 1 : 0
  filename = "${local.generated_apps_dir}/sentiment-auth-uat.yaml"
  content  = templatefile("${path.module}/templates/apps/sentiment-auth-uat.yaml.tpl", local.app_template_vars)
}

# Azure Auth Sim deployment files
resource "local_file" "nginx_gateway_fabric_deploy" {
  count    = var.enable_azure_auth_sim ? 1 : 0
  filename = "${local.generated_apps_dir}/nginx-gateway-fabric/deploy.yaml"
  content  = templatefile("${path.module}/templates/apps/nginx-gateway-fabric/deploy.yaml.tpl", local.app_template_vars)
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

locals {
  # CA cert path for external Gitea registry - used by Kind nodes for containerd TLS
  gitea_ca_cert_path = abspath("${path.module}/certs/ca.crt")

  # Docker socket mount for in-cluster Actions runner (host socket approach)
  # Kept independent from enable_actions_runner so the Kind cluster config stays stable across stages
  docker_socket_mount = var.enable_docker_socket_mount && !var.use_external_gitea ? [
    {
      host_path      = var.docker_socket_path
      container_path = "/var/run/docker.sock"
      registry_host  = ""
      read_only      = false
    }
  ] : []

  # Extra mounts for Kind nodes - mount CA cert when using external Gitea
  # registry_host is explicitly passed for containerd config (avoids path parsing in template)
  kind_extra_mounts = concat(
    var.use_external_gitea ? [
      {
        host_path      = local.gitea_ca_cert_path
        container_path = "/etc/containerd/certs.d/${var.gitea_registry_host}/ca.crt"
        registry_host  = var.gitea_registry_host
        read_only      = true
      }
    ] : [],
    local.docker_socket_mount
  )
}

resource "local_file" "kind_config" {
  filename = var.kind_config_path
  content = templatefile("${path.module}/templates/kind-config.yaml.tpl", {
    workers      = local.kind_workers
    ports        = local.extra_port_mappings
    extra_mounts = local.kind_extra_mounts
    # For in-cluster Gitea, configure containerd to allow HTTP registry
    insecure_registry = var.use_external_gitea ? "" : "gitea-http.gitea.svc.cluster.local:3000"
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

    # Configure containerd registry access:
    # - External Gitea: trust the CA cert for HTTPS registry
    # - In-cluster Gitea: allow insecure HTTP registry using gitea_registry_host (e.g., localhost:30090)
    #   Note: containerd runs on nodes, not pods, so it cannot resolve Kubernetes DNS names.
    #   For in-cluster Gitea, use localhost:NodePort which Kind nodes can access.
    containerd_config_patches = var.use_external_gitea ? [
      <<-EOT
      [plugins."io.containerd.grpc.v1.cri".registry.configs."${var.gitea_registry_host}".tls]
        ca_file = "/etc/containerd/certs.d/${var.gitea_registry_host}/ca.crt"
      EOT
      ] : [
      <<-EOT
      [plugins."io.containerd.grpc.v1.cri".registry.configs."${var.gitea_registry_host}".tls]
        insecure_skip_verify = true
      EOT
    ]

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

      dynamic "extra_mounts" {
        for_each = local.kind_extra_mounts
        content {
          host_path      = extra_mounts.value.host_path
          container_path = extra_mounts.value.container_path
          read_only      = extra_mounts.value.read_only
        }
      }
    }

    dynamic "node" {
      for_each = local.kind_workers
      content {
        role = "worker"

        dynamic "extra_mounts" {
          for_each = local.kind_extra_mounts
          content {
            host_path      = extra_mounts.value.host_path
            container_path = extra_mounts.value.container_path
            read_only      = extra_mounts.value.read_only
          }
        }
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

# If mkcert is installed on the host, automatically bootstrap the mkcert CA into the cluster.
# This unblocks cert-manager's mkcert-ca ClusterIssuer so gateway TLS certs can be issued.
resource "null_resource" "bootstrap_mkcert_ca" {
  count = var.enable_azure_auth_ports ? 1 : 0

  triggers = {
    script_sha = filesha256(abspath("${path.module}/scripts/bootstrap-mkcert-ca.sh"))
  }

  provisioner "local-exec" {
    command     = <<-EOT
set -euo pipefail
export KUBECONFIG=~/.kube/config

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert not found; skipping mkcert CA bootstrap" >&2
  exit 0
fi

CAROOT="$(mkcert -CAROOT)"
if [ ! -f "$CAROOT/rootCA.pem" ] || [ ! -f "$CAROOT/rootCA-key.pem" ]; then
  echo "mkcert CA files not present under $CAROOT; run 'mkcert -install' then re-apply" >&2
  exit 0
fi

bash "${path.module}/scripts/bootstrap-mkcert-ca.sh"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

# When platform SSO is enabled, ArgoCD needs to resolve the Keycloak issuer hostname from inside the cluster.
# sslip.io hostnames resolve to 127.0.0.1 by default, so we add a CoreDNS rewrite that points the login hostname
# at the in-cluster Gateway dataplane service.
resource "null_resource" "patch_coredns_login_host" {
  count = var.enable_platform_sso ? 1 : 0

  triggers = {
    script_sha  = filesha256(abspath("${path.module}/scripts/patch-coredns-rewrite-login-host.sh"))
    login_host  = var.platform_sso_keycloak_host
    target_host = "azure-auth-gateway-nginx.azure-auth-gateway.svc.cluster.local"
  }

  provisioner "local-exec" {
    command     = <<-EOT
set -euo pipefail
export KUBECONFIG=~/.kube/config

bash "${path.module}/scripts/patch-coredns-rewrite-login-host.sh" \
  "${var.platform_sso_keycloak_host}" \
  "azure-auth-gateway-nginx.azure-auth-gateway.svc.cluster.local"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
    null_resource.bootstrap_mkcert_ca,
  ]
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

resource "kubernetes_secret" "gitea_admin" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0

  metadata {
    name      = "gitea-admin-secret"
    namespace = kubernetes_namespace.gitea[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    # The Gitea Helm chart's init flow expects these exact keys.
    username = var.gitea_admin_username
    password = var.gitea_admin_pwd

    # Backwards-compatible key used by our Helm values.
    adminPwd = var.gitea_admin_pwd
  }

  depends_on = [kubernetes_namespace.gitea[0]]
}

resource "kubernetes_secret" "gitea_oidc" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0

  metadata {
    name      = "gitea-oidc-secret"
    namespace = kubernetes_namespace.gitea[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    key    = var.gitea_oidc_client_id
    secret = var.gitea_oidc_client_secret
  }

  depends_on = [kubernetes_namespace.gitea[0]]
}

resource "kubernetes_namespace" "kyverno" {
  count = var.enable_namespaces ? 1 : 0

  metadata {
    name = "kyverno"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubectl_manifest" "azure_auth_namespace" {
  for_each = var.enable_azure_auth_sim ? var.azure_auth_namespaces : {}

  ignore_fields = [
    "metadata.annotations",
    "metadata.creationTimestamp",
    "metadata.labels.kubernetes.io/metadata.name",
    "metadata.labels.argocd.argoproj.io/instance",
    "metadata.managedFields",
    "metadata.resourceVersion",
    "metadata.uid",
    "spec.finalizers",
    "status",
  ]

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${each.value}
  labels:
    app.kubernetes.io/part-of: azure-auth-sim
    app.kubernetes.io/managed-by: terraform
    environment: ${each.key}
    azure-auth-gateway-access: "true"
    kyverno.io/isolate: "true"
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

resource "kubectl_manifest" "azure_auth_gateway_namespace" {
  count = var.enable_azure_auth_sim ? 1 : 0

  ignore_fields = [
    "metadata.annotations",
    "metadata.creationTimestamp",
    "metadata.labels.kubernetes.io/metadata.name",
    "metadata.labels.argocd.argoproj.io/instance",
    "metadata.managedFields",
    "metadata.resourceVersion",
    "metadata.uid",
    "spec.finalizers",
    "status",
  ]

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.azure_auth_gateway_namespace}
  labels:
    app.kubernetes.io/part-of: azure-auth-sim
    app.kubernetes.io/managed-by: terraform
    kyverno.io/isolate: "true"
    simulates: azure-auth-gateway
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

resource "kubectl_manifest" "azure_entraid_namespace" {
  count = var.enable_azure_auth_sim && var.enable_azure_entraid_sim ? 1 : 0

  ignore_fields = [
    "metadata.annotations",
    "metadata.creationTimestamp",
    "metadata.labels.kubernetes.io/metadata.name",
    "metadata.labels.argocd.argoproj.io/instance",
    "metadata.managedFields",
    "metadata.resourceVersion",
    "metadata.uid",
    "spec.finalizers",
    "status",
  ]

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.azure_entraid_namespace}
  labels:
    app.kubernetes.io/part-of: azure-auth-sim
    app.kubernetes.io/managed-by: terraform
    kyverno.io/isolate: "true"
    simulates: azure-entra-id
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

resource "kubectl_manifest" "azure_apim_namespace" {
  count = var.enable_azure_auth_sim ? 1 : 0

  ignore_fields = [
    "metadata.annotations",
    "metadata.creationTimestamp",
    "metadata.labels.kubernetes.io/metadata.name",
    "metadata.labels.argocd.argoproj.io/instance",
    "metadata.managedFields",
    "metadata.resourceVersion",
    "metadata.uid",
    "spec.finalizers",
    "status",
  ]

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.azure_apim_namespace}
  labels:
    app.kubernetes.io/part-of: azure-auth-sim
    app.kubernetes.io/managed-by: terraform
    kyverno.io/isolate: "true"
    simulates: azure-apim
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

resource "kubectl_manifest" "sentiment_namespace" {
  count = var.enable_llm_sentiment ? 1 : 0

  ignore_fields = [
    "metadata.annotations",
    "metadata.creationTimestamp",
    "metadata.labels.kubernetes.io/metadata.name",
    "metadata.labels.argocd.argoproj.io/instance",
    "metadata.managedFields",
    "metadata.resourceVersion",
    "metadata.uid",
    "spec.finalizers",
    "status",
  ]

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: sentiment
  labels:
    app.kubernetes.io/part-of: sentiment
    app.kubernetes.io/managed-by: terraform
    kyverno.io/isolate: "true"
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

resource "kubectl_manifest" "sentiment_llm_namespace" {
  count = var.enable_llm_sentiment ? 1 : 0

  ignore_fields = [
    "metadata.annotations",
    "metadata.creationTimestamp",
    "metadata.labels.kubernetes.io/metadata.name",
    "metadata.labels.argocd.argoproj.io/instance",
    "metadata.managedFields",
    "metadata.resourceVersion",
    "metadata.uid",
    "spec.finalizers",
    "status",
  ]

  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: sentiment-llm
  labels:
    app.kubernetes.io/part-of: sentiment
    app.kubernetes.io/managed-by: terraform
    kyverno.io/isolate: "true"
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

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 1800

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
    # If the cluster/kubeconfig is recreated, we must re-wait for the new Gitea deployment.
    cluster_id    = kind_cluster.local.id
    kubeconfig_id = local_sensitive_file.kubeconfig.id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG=${var.kubeconfig_path}

# Wait for ArgoCD to reconcile the Helm release (including dependency changes like valkey settings).
# We cannot rely on a short Deployment rollout timeout here because ArgoCD may need to prune/create
# dependent resources first.
for i in {1..120}; do
  if kubectl -n argocd get app gitea >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for ArgoCD Application 'gitea' to exist... (attempt $i/120)" >&2
  sleep 5
done

for i in {1..120}; do
  sync=$(kubectl -n argocd get app gitea -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n argocd get app gitea -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
    echo "ArgoCD app gitea is Synced/Healthy."
    break
  fi
  msg=$(kubectl -n argocd get app gitea -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "")
  echo "Waiting for ArgoCD app gitea... (attempt $i/180) sync=$sync health=$health $${msg}" >&2
  # If ArgoCD is stuck in Unknown due to transient compare failures, force a hard refresh.
  if [ "$sync" = "Unknown" ]; then
    kubectl -n argocd annotate app gitea argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  fi
  sleep 10
done

kubectl -n gitea rollout status deploy/gitea --timeout=900s
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    helm_release.argocd[0],
    kubectl_manifest.argocd_app_gitea[0]
  ]
}

resource "tls_private_key" "gitea_repo" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0


  algorithm = "ED25519"
}

resource "tls_private_key" "gitea_repo_azure_auth" {
  count = var.enable_gitea && var.enable_actions_runner && !var.use_external_gitea ? 1 : 0

  algorithm = "ED25519"
}

resource "null_resource" "gitea_create_repo" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0


  triggers = {
    rollout = null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
    -H "Content-Type: application/json" \
    -d '{"name":"policies","private":false,"default_branch":"main","auto_init":true,"description":"Policies for Cilium and Kyverno"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/repos || echo "000")
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
  count = var.enable_gitea && var.enable_actions_runner && !var.use_external_gitea ? 1 : 0


  triggers = {
    rollout = null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
    -H "Content-Type: application/json" \
    -d '{"name":"azure-auth-sim","private":false,"default_branch":"main","auto_init":true,"description":"Azure auth simulation workloads (API/APIM simulator/frontend)"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/repos || echo "000")
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

resource "null_resource" "gitea_create_repo_sentiment_auth" {
  count = var.enable_gitea && var.enable_actions_runner && var.enable_sentiment_auth_frontend && !var.use_external_gitea ? 1 : 0

  triggers = {
    rollout = null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
    -H "Content-Type: application/json" \
    -d '{"name":"sentiment-auth-ui","private":false,"default_branch":"main","auto_init":true,"description":"Sentiment authenticated UI (oauth2-proxy + React)"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/repos || echo "000")
  if echo "$status" | grep -Eq "200|201|409"; then
    exit 0
  fi
  echo "Gitea sentiment-auth-ui repo create returned HTTP $status, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to create sentiment-auth-ui repo in Gitea" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "null_resource" "gitea_create_repo_sentiment_api" {
  count = var.enable_gitea && var.enable_actions_runner && var.enable_llm_sentiment && !var.use_external_gitea ? 1 : 0

  triggers = {
    rollout = null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
    -H "Content-Type: application/json" \
    -d '{"name":"sentiment-api","private":false,"default_branch":"main","auto_init":true,"description":"Sentiment API (LLM inference + CSV persistence)"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/repos || echo "000")
  if echo "$status" | grep -Eq "200|201|409"; then
    exit 0
  fi
  echo "Gitea sentiment-api repo create returned HTTP $status, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to create sentiment-api repo in Gitea" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "null_resource" "gitea_add_deploy_key" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0


  triggers = {
    repo    = null_resource.gitea_create_repo[0].id
    ssh_key = tls_private_key.gitea_repo[0].public_key_openssh
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
    -H "Content-Type: application/json" \
    -d '{"title":"argocd-repo-key","key":"${tls_private_key.gitea_repo[0].public_key_openssh}","read_only":false}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/policies/keys || echo "000")
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
  count = var.enable_gitea && var.enable_actions_runner && !var.use_external_gitea ? 1 : 0


  triggers = {
    repo    = null_resource.gitea_create_repo_azure_auth[0].id
    ssh_key = tls_private_key.gitea_repo_azure_auth[0].public_key_openssh
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
for i in {1..20}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
    -H "Content-Type: application/json" \
    -d '{"title":"azure-auth-repo-key","key":"${tls_private_key.gitea_repo_azure_auth[0].public_key_openssh}","read_only":false}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/azure-auth-sim/keys || echo "000")
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
# Skipped when use_external_gitea=true because stage100 creates .run/gitea_known_hosts
resource "null_resource" "gitea_known_hosts" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0

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

  depends_on = [null_resource.gitea_create_repo]
}

# Cluster-internal known_hosts for ArgoCD (gitea-ssh.gitea.svc.cluster.local:22)
# Still needed for external Gitea - ArgoCD needs to SSH to Gitea from inside cluster
resource "null_resource" "gitea_known_hosts_cluster" {
  count = var.enable_gitea ? 1 : 0

  triggers = {
    # For external Gitea, use static trigger; for in-cluster, depend on repo creation
    gitea_setup = var.use_external_gitea ? "external" : null_resource.gitea_create_repo[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
mkdir -p "${path.module}/.run"
for i in {1..20}; do
  if kubectl run ssh-keyscan-$$ --image=alpine:latest --rm -i --restart=Never -q -- \
    sh -c "apk add --no-cache openssh-client >/dev/null 2>&1 && ssh-keyscan -p ${local.gitea_ssh_port_cluster} ${local.gitea_ssh_host_cluster} 2>/dev/null" \
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

  depends_on = [null_resource.gitea_create_repo]
}

data "local_file" "gitea_known_hosts" {
  count    = var.enable_gitea ? 1 : 0
  filename = local.gitea_known_hosts
  # For external Gitea, stage100 creates this file; for in-cluster, null_resource creates it
  depends_on = [null_resource.gitea_known_hosts]
}

data "local_file" "gitea_known_hosts_cluster" {
  count      = var.enable_gitea ? 1 : 0
  filename   = local.gitea_known_hosts_cluster
  depends_on = [null_resource.gitea_known_hosts_cluster]
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
GITEA_KEY=$(grep -E "^[^#]" "${local.gitea_known_hosts_cluster}" | grep "${local.gitea_ssh_host_cluster}" | head -1)

# Check if already present
if ! grep -q "${local.gitea_ssh_host_cluster}" /tmp/argocd-known-hosts.txt; then
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
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0


  content              = tls_private_key.gitea_repo[0].private_key_openssh
  filename             = local.gitea_repo_key_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_sensitive_file" "gitea_azure_auth_repo_private_key" {
  count = var.enable_gitea && var.enable_actions_runner && !var.use_external_gitea ? 1 : 0

  content              = tls_private_key.gitea_repo_azure_auth[0].private_key_openssh
  filename             = local.azure_auth_repo_key_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "null_resource" "seed_gitea_repo" {
  count = var.enable_gitea && !var.use_external_gitea ? 1 : 0


  triggers = {
    repo_id    = null_resource.gitea_create_repo[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.repo_checksum
    # Trigger on generated file changes
    generated_files = md5(join("", [
      local_file.app_cilium_policies.content,
      local_file.app_kyverno_policies.content,
      var.enable_policies ? local_file.app_kyverno[0].content : "",
      var.enable_signoz_k8s_infra ? local_file.app_signoz_k8s_infra[0].content : "",
      var.enable_azure_auth_sim && var.enable_subnetcalc_azure_auth_sim ? local_file.app_azure_auth_sim_dev[0].content : "",
      var.enable_azure_auth_sim && var.enable_subnetcalc_azure_auth_sim ? local_file.app_azure_auth_sim_uat[0].content : "",
      var.enable_azure_auth_sim && var.enable_azure_entraid_sim ? local_file.app_azure_entraid_sim[0].content : "",
      var.enable_azure_auth_sim ? local_file.app_azure_apim_sim[0].content : "",
      var.enable_actions_runner && !var.use_external_gitea ? local_file.app_gitea_actions_runner[0].content : "",
      var.enable_azure_auth_sim ? local_file.app_nginx_gateway_fabric[0].content : "",
      var.enable_azure_auth_sim ? local_file.nginx_gateway_fabric_deploy[0].content : "",
      var.enable_azure_auth_sim ? local_file.app_platform_gateway_routes[0].content : "",
      var.enable_sentiment_auth_frontend ? local_file.app_sentiment_auth_dev[0].content : "",
      var.enable_sentiment_auth_frontend ? local_file.app_sentiment_auth_uat[0].content : "",
      "",
    ]))
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
if [ "${var.use_external_gitea}" = "true" ]; then
  echo "External Gitea detected; skipping Terraform seeding (stage scripts handle this)." >&2
  exit 0
fi
TMP_DIR=$(mktemp -d)

# Copy base apps directory (non-templated files: services, kustomization, etc.)
cp -r ${path.module}/apps "$TMP_DIR"/

# Remove all old static app YAML files that are now templated
rm -f "$TMP_DIR/apps/"*.yaml

# Copy generated app directories (e.g., nginx-gateway-fabric/deploy.yaml)
for item in ${local.generated_apps_dir}/*; do
  if [ -d "$item" ]; then
    cp -r "$item" "$TMP_DIR/apps/"
  fi
done

# Copy generated ArgoCD Application YAMLs into the app-of-apps folder
mkdir -p "$TMP_DIR/apps/_applications"
shopt -s nullglob
for f in ${local.generated_apps_dir}/*.yaml; do
  cp -f "$f" "$TMP_DIR/apps/_applications/"
done
shopt -u nullglob

if [ "${var.enable_azure_auth_sim}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/azure-auth-sim-dev.yaml" "$TMP_DIR/apps/_applications/azure-auth-sim-uat.yaml"
  rm -f "$TMP_DIR/apps/_applications/azure-auth-gateway.yaml"
  rm -f "$TMP_DIR/apps/_applications/azure-entraid-sim.yaml"
  rm -f "$TMP_DIR/apps/_applications/azure-apim-sim.yaml"
  rm -f "$TMP_DIR/apps/_applications/nginx-gateway-fabric.yaml"
  rm -f "$TMP_DIR/apps/_applications/platform-gateway-routes.yaml"
fi

if [ "${var.enable_subnetcalc_azure_auth_sim}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/azure-auth-sim-dev.yaml" "$TMP_DIR/apps/_applications/azure-auth-sim-uat.yaml"
fi

if [ "${var.enable_azure_entraid_sim}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/azure-entraid-sim.yaml"
fi

# Deprecated app name/path cleanup (replaced by sentiment-core/sentiment-dev/sentiment-uat)
rm -f "$TMP_DIR/apps/_applications/llm-sentiment.yaml"
rm -rf "$TMP_DIR/apps/llm-sentiment"

if [ "${var.enable_llm_sentiment}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/sentiment-core.yaml"
  rm -f "$TMP_DIR/apps/_applications/sentiment-dev.yaml"
  rm -f "$TMP_DIR/apps/_applications/sentiment-uat.yaml"
fi

if [ "${var.enable_sentiment_auth_frontend}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/sentiment-auth-dev.yaml"
  rm -f "$TMP_DIR/apps/_applications/sentiment-auth-uat.yaml"
fi
if [ "${var.enable_actions_runner}" != "true" ] || [ "${var.use_external_gitea}" = "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/gitea-actions-runner.yaml"
  rm -rf "$TMP_DIR/apps/gitea-actions-runner"
fi

if [ "${var.enable_victoria_metrics}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/victoria-metrics.yaml"
fi

if [ "${var.enable_signoz}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/signoz.yaml"
fi

if [ "${var.enable_signoz_k8s_infra}" != "true" ]; then
  rm -f "$TMP_DIR/apps/_applications/signoz-k8s-infra.yaml"
fi

    cp -r ${path.module}/cluster-policies "$TMP_DIR"/cluster-policies
cd "$TMP_DIR"
git init -q
git config user.email "argocd@gitea.local"
git config user.name "argocd"
git config commit.gpgsign false
git add .
git commit -q -m "Seed policies"
git branch -M main
git remote add origin ${local.gitea_http_scheme}://${var.gitea_http_host_local}:${var.gitea_http_port}/${var.gitea_admin_username}/policies.git

ASKPASS=$(mktemp)
trap 'rm -f "$ASKPASS"' EXIT
cat > "$ASKPASS" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) echo "$GITEA_USERNAME" ;;
  *Password*) echo "$GITEA_PWD" ;;
  *) echo "" ;;
esac
EOF
chmod +x "$ASKPASS"
GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS="$ASKPASS" \
  GITEA_USERNAME="${var.gitea_admin_username}" \
  GITEA_PWD="${var.gitea_admin_pwd}" \
  git push -f origin main
rm -f "$ASKPASS"
trap - EXIT
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    local_file.app_cilium_policies,
    local_file.app_kyverno_policies,
    local_file.app_kyverno,
    local_file.app_signoz_k8s_infra,
    local_file.app_azure_auth_sim_dev,
    local_file.app_azure_auth_sim_uat,
    local_file.app_azure_entraid_sim,
    local_file.app_azure_apim_sim,
    local_file.app_sentiment_auth_dev,
    local_file.app_sentiment_auth_uat,
    local_file.app_gitea_actions_runner,
    local_file.app_nginx_gateway_fabric,
    local_file.nginx_gateway_fabric_deploy,
    local_file.app_platform_gateway_routes,
  ]
}

resource "null_resource" "seed_gitea_repo_azure_auth" {
  count = var.enable_gitea && var.enable_actions_runner && !var.use_external_gitea ? 1 : 0


  triggers = {
    repo_id    = null_resource.gitea_create_repo_azure_auth[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.azure_auth_repo_checksum
    password   = md5(var.gitea_admin_pwd)
    registry   = md5(local.gitea_registry_host)
  }

  provisioner "local-exec" {
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
git remote add origin ${local.gitea_http_scheme}://${var.gitea_http_host_local}:${var.gitea_http_port}/${var.gitea_admin_username}/azure-auth-sim.git

ASKPASS=$(mktemp)
trap 'rm -f "$ASKPASS"' EXIT
cat > "$ASKPASS" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) echo "$GITEA_USERNAME" ;;
  *Password*) echo "$GITEA_PWD" ;;
  *) echo "" ;;
esac
EOF
chmod +x "$ASKPASS"
GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS="$ASKPASS" \
  GITEA_USERNAME="${var.gitea_admin_username}" \
  GITEA_PWD="${var.gitea_admin_pwd}" \
  git push -f origin main
rm -f "$ASKPASS"
trap - EXIT
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Ensure repo secrets exist before the initial push triggers the Actions workflow.
  depends_on = [
    null_resource.gitea_azure_auth_repo_secrets_internal[0]
  ]
}

resource "null_resource" "seed_gitea_repo_sentiment_auth" {
  count = var.enable_gitea && var.enable_actions_runner && var.enable_sentiment_auth_frontend && !var.use_external_gitea ? 1 : 0

  triggers = {
    repo_id    = null_resource.gitea_create_repo_sentiment_auth[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.sentiment_auth_repo_checksum
    password   = md5(var.gitea_admin_pwd)
    registry   = md5(local.gitea_registry_host)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
if [ "${var.use_external_gitea}" = "true" ]; then
  echo "External Gitea detected; skipping Terraform seeding (stage scripts handle this)." >&2
  exit 0
fi
TMP_DIR=$(mktemp -d)
cp -r ${local.sentiment_auth_ui_root}/. "$TMP_DIR"/
cd "$TMP_DIR"
git init -q
git config user.email "argocd@gitea.local"
git config user.name "argocd"
git config commit.gpgsign false
git add .
git commit -q -m "Seed sentiment-auth-ui sources"
git branch -M main
git remote add origin ${local.gitea_http_scheme}://${var.gitea_http_host_local}:${var.gitea_http_port}/${var.gitea_admin_username}/sentiment-auth-ui.git

ASKPASS=$(mktemp)
trap 'rm -f "$ASKPASS"' EXIT
cat > "$ASKPASS" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) echo "$GITEA_USERNAME" ;;
  *Password*) echo "$GITEA_PWD" ;;
  *) echo "" ;;
esac
EOF
chmod +x "$ASKPASS"
GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS="$ASKPASS" \
  GITEA_USERNAME="${var.gitea_admin_username}" \
  GITEA_PWD="${var.gitea_admin_pwd}" \
  git push -f origin main
rm -f "$ASKPASS"
trap - EXIT
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Ensure repo secrets exist before the initial push triggers the Actions workflow.
  depends_on = [
    null_resource.gitea_sentiment_auth_repo_secrets_internal[0]
  ]
}

resource "null_resource" "seed_gitea_repo_sentiment_api" {
  count = var.enable_gitea && var.enable_actions_runner && var.enable_llm_sentiment && !var.use_external_gitea ? 1 : 0

  triggers = {
    repo_id    = null_resource.gitea_create_repo_sentiment_api[0].id
    host_key   = md5(data.local_file.gitea_known_hosts[0].content)
    repo_files = local.sentiment_api_repo_checksum
    password   = md5(var.gitea_admin_pwd)
    registry   = md5(local.gitea_registry_host)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
if [ "${var.use_external_gitea}" = "true" ]; then
  echo "External Gitea detected; skipping Terraform seeding (stage scripts handle this)." >&2
  exit 0
fi
TMP_DIR=$(mktemp -d)

# Copy sources without node_modules/ (people may have run npm install locally).
tar --exclude='node_modules' -C ${local.sentiment_api_root} -cf - . | tar -C "$TMP_DIR" -xf -

cd "$TMP_DIR"
git init -q
git config user.email "argocd@gitea.local"
git config user.name "argocd"
git config commit.gpgsign false
git add .
git commit -q -m "Seed sentiment-api sources"
git branch -M main
git remote add origin ${local.gitea_http_scheme}://${var.gitea_http_host_local}:${var.gitea_http_port}/${var.gitea_admin_username}/sentiment-api.git

ASKPASS=$(mktemp)
trap 'rm -f "$ASKPASS"' EXIT
cat > "$ASKPASS" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) echo "$GITEA_USERNAME" ;;
  *Password*) echo "$GITEA_PWD" ;;
  *) echo "" ;;
esac
EOF
chmod +x "$ASKPASS"
GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS="$ASKPASS" \
  GITEA_USERNAME="${var.gitea_admin_username}" \
  GITEA_PWD="${var.gitea_admin_pwd}" \
  git push -f origin main
rm -f "$ASKPASS"
trap - EXIT
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Ensure repo secrets exist before the initial push triggers the Actions workflow.
  depends_on = [
    null_resource.gitea_sentiment_api_repo_secrets_internal[0]
  ]
}

# For external Gitea (not currently used - external build process handles this)
# For in-cluster Gitea, use gitea_azure_auth_repo_secrets_internal instead
resource "null_resource" "gitea_azure_auth_repo_secrets" {
  count = 0 # Disabled: use _internal for in-cluster, external build for external Gitea


  triggers = {
    repo_id  = null_resource.gitea_create_repo_azure_auth[0].id
    password = md5(var.gitea_admin_pwd)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
create_secret() {
  local name="$1"
  local value="$2"
  for i in {1..5}; do
    status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X PUT \
      -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":\"$${value}\"}" \
      ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/azure-auth-sim/actions/secrets/$${name} || echo "000")
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
create_secret "REGISTRY_PWD" "${var.gitea_admin_pwd}"
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
    type = "git"
    url  = "ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host_cluster}:${local.gitea_ssh_port_cluster}/${var.gitea_admin_username}/policies.git"
    # Use Terraform-generated SSH key (added to Gitea admin user for external, or as deploy key for in-cluster)
    sshPrivateKey = var.use_external_gitea ? tls_private_key.argocd_repo[0].private_key_openssh : tls_private_key.gitea_repo[0].private_key_openssh
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
    null_resource.gitea_add_deploy_key,
    null_resource.gitea_add_user_ssh_key,
    null_resource.gitea_known_hosts_cluster,
    data.local_file.gitea_known_hosts_cluster,
    null_resource.seed_gitea_repo,
    local_sensitive_file.kubeconfig
  ]
}

resource "kubernetes_secret" "azure_auth_registry_credentials" {
  for_each = var.enable_azure_auth_sim ? var.azure_auth_namespaces : {}

  metadata {
    name      = "gitea-registry-creds"
    namespace = each.value
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.gitea_registry_host) = {
          auth = base64encode("${var.gitea_admin_username}:${var.gitea_admin_pwd}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [
    kubectl_manifest.azure_auth_namespace
  ]
}

# Registry credentials for azure-apim-sim namespace (APIM pulls images from Gitea)
resource "kubernetes_secret" "azure_apim_registry_credentials" {
  count = var.enable_azure_auth_sim ? 1 : 0

  metadata {
    name      = "gitea-registry-creds"
    namespace = var.azure_apim_namespace
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.gitea_registry_host) = {
          auth = base64encode("${var.gitea_admin_username}:${var.gitea_admin_pwd}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [
    kubectl_manifest.azure_apim_namespace[0]
  ]
}

resource "kubernetes_secret" "sentiment_registry_credentials" {
  for_each = var.enable_llm_sentiment ? {
    sentiment     = "sentiment"
    sentiment_llm = "sentiment-llm"
  } : {}

  metadata {
    name      = "gitea-registry-creds"
    namespace = each.value
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.gitea_registry_host) = {
          auth = base64encode("${var.gitea_admin_username}:${var.gitea_admin_pwd}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [
    kubectl_manifest.sentiment_namespace,
    kubectl_manifest.sentiment_llm_namespace,
  ]
}

# SSH key for ArgoCD to access Gitea repos (generated regardless of external Gitea)
# NOTE: Uses OpenSSH format (private_key_openssh) instead of PEM format for better
# compatibility with modern SSH clients. If you have existing deployments expecting
# PEM format, use tls_private_key.argocd_repo[0].private_key_pem instead.
resource "tls_private_key" "argocd_repo" {
  count = var.generate_repo_ssh_key ? 1 : 0

  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  count           = var.generate_repo_ssh_key ? 1 : 0
  content         = tls_private_key.argocd_repo[0].private_key_openssh
  filename        = var.ssh_private_key_path
  file_permission = "0600"
  depends_on      = [tls_private_key.argocd_repo]
}

resource "local_file" "ssh_public_key" {
  count    = var.generate_repo_ssh_key ? 1 : 0
  content  = tls_private_key.argocd_repo[0].public_key_openssh
  filename = var.ssh_public_key_path
}

# For external Gitea, add the Terraform-generated SSH key to the admin user
# Uses an API credential because basic auth doesn't work for /user/keys endpoint
resource "null_resource" "gitea_add_user_ssh_key" {
  count = var.enable_gitea && var.use_external_gitea && var.generate_repo_ssh_key ? 1 : 0

  triggers = {
    ssh_key = tls_private_key.argocd_repo[0].public_key_openssh
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
# Create API credential for calls (basic auth doesn't work for /user/keys)
ACCESS=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"argocd-ssh-key-$(date +%s)\",\"scopes\":[\"write:user\"]}" \
  ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/users/${var.gitea_admin_username}/tokens 2>/dev/null || echo '{}')
ACCESS=$(echo "$ACCESS" | jq -r '.sha1 // empty')
if [ -z "$ACCESS" ]; then
  echo "Failed to create API credential" >&2
  exit 1
fi
# Add SSH key using credential
AUTH_PREFIX=token
AUTH_HEADER="Authorization: $AUTH_PREFIX $ACCESS"
for i in {1..10}; do
  status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{"title":"argocd-terraform-key","key":"${chomp(tls_private_key.argocd_repo[0].public_key_openssh)}"}' \
    ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/user/keys || echo "000")
  if echo "$status" | grep -Eq "200|201|422"; then
    exit 0
  fi
  echo "Adding SSH key to Gitea user returned HTTP $status, retrying... ($i/10)" >&2
  sleep 3
done
echo "Failed to add SSH key to Gitea user" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [tls_private_key.argocd_repo]
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
        # Valkey cluster tends to flap / split-brain on kind which can crash Gitea on startup.
        # Use standalone Valkey for a reliable local dev experience.
        valkey-cluster:
          enabled: false
        valkey:
          enabled: true
          architecture: standalone
          global:
            valkey:
              password: changeme
        gitea:
          admin:
            existingSecret: gitea-admin-secret
            passwordKey: password
            username: ${var.gitea_admin_username}
            email: "admin@gitea.local"
          config:
            server:
              DISABLE_SSH: false
              SSH_PORT: ${var.gitea_ssh_node_port}
              DOMAIN: gitea.127.0.0.1.sslip.io
              ROOT_URL: https://gitea.127.0.0.1.sslip.io/
            openid:
              ENABLE_OPENID_SIGNIN: true
              ENABLE_OPENID_SIGNUP: true
            oauth2_client:
              ENABLE_AUTO_REGISTRATION: true
              ACCOUNT_LINKING: auto
              USERNAME: preferred_username
              OPENID_CONNECT_SCOPES: openid profile email
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
    kubernetes_namespace.gitea[0],
    kubernetes_secret.gitea_admin,
    kubernetes_secret.gitea_oidc,
  ]
}

# App of Apps - root application that manages all child applications
# Child apps are defined in apps/ and synced from Gitea
resource "kubectl_manifest" "argocd_app_of_apps" {
  count = var.enable_gitea && (var.enable_policies || var.enable_azure_auth_sim || var.enable_llm_sentiment) ? 1 : 0

  ignore_fields = [
    "metadata.annotations",
    "metadata.labels",
    "metadata.finalizers",
    "status",
  ]

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
    repoURL: ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host_cluster}:${local.gitea_ssh_port_cluster}/${var.gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/_applications
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
    kubernetes_secret.argocd_repo_gitea[0],
    null_resource.seed_gitea_repo[0],
    null_resource.argocd_add_gitea_known_host[0]
  ]
}

# Post-bootstrap: configure Gitea OIDC *after* Keycloak exists.
# Keycloak is deployed from the policies repo hosted on Gitea, so baking this into the Helm chart init
# container creates a cyclic dependency (Gitea fails before Keycloak exists). Instead, we configure the
# auth source as soon as Keycloak is reachable (avoids waiting for ArgoCD health to flip).
resource "null_resource" "gitea_configure_oidc" {
  count = var.enable_platform_sso && var.enable_gitea && var.enable_azure_auth_sim && var.enable_azure_entraid_sim && !var.use_external_gitea ? 1 : 0

  triggers = {
    cluster_id           = kind_cluster.local.id
    kubeconfig_id        = local_sensitive_file.kubeconfig.id
    gitea_app_id         = null_resource.wait_for_gitea[0].id
    app_of_apps_revision = kubectl_manifest.argocd_app_of_apps[0].id
    keycloak_host        = var.platform_sso_keycloak_host
    gitea_oidc_client_id = var.gitea_oidc_client_id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG=${var.kubeconfig_path}

AUTO_URL="http://keycloak.azure-entraid-sim.svc.cluster.local:8080/realms/subnet-calculator/.well-known/openid-configuration"

CLIENT_ID=$(kubectl -n gitea get secret gitea-oidc-secret -o jsonpath='{.data.key}' | base64 -d)
CLIENT_SECRET=$(kubectl -n gitea get secret gitea-oidc-secret -o jsonpath='{.data.secret}' | base64 -d)

for i in {1..120}; do
  sync=$(kubectl -n argocd get app azure-entraid-sim -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n argocd get app azure-entraid-sim -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  kc_ready=$(kubectl -n azure-entraid-sim get deploy keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "")
  kc_total=$(kubectl -n azure-entraid-sim get deploy keycloak -o jsonpath='{.status.replicas}' 2>/dev/null || echo "")
  if [ -n "$kc_total" ]; then
    echo "Keycloak rollout: $${kc_ready:-0}/$kc_total available; Argo azure-entraid-sim: sync=$sync health=$health" >&2
  else
    echo "Waiting for Keycloak to exist; Argo azure-entraid-sim: sync=$sync health=$health" >&2
  fi

  AUTH_ID=$(kubectl -n gitea exec deploy/gitea -c gitea -- gitea admin auth list --vertical-bars 2>/dev/null \
    | awk -F'|' '$2 ~ /Keycloak/ && $3 ~ /OAuth2/ {gsub(/ /,"",$1); print $1; exit}')

  if [ -z "$AUTH_ID" ]; then
    echo "Creating Gitea auth source 'Keycloak'... (attempt $i/120)" >&2
    if kubectl -n gitea exec deploy/gitea -c gitea -- gitea admin auth add-oauth \
      --auto-discover-url "$AUTO_URL" \
      --key "$CLIENT_ID" \
      --name "Keycloak" \
      --provider "openidConnect" \
      --secret "$CLIENT_SECRET" >/dev/null 2>&1; then
      echo "Gitea auth source 'Keycloak' created." >&2
      exit 0
    fi
  else
    echo "Updating Gitea auth source 'Keycloak' (id=$AUTH_ID)... (attempt $i/120)" >&2
    if kubectl -n gitea exec deploy/gitea -c gitea -- gitea admin auth update-oauth \
      --id "$AUTH_ID" \
      --auto-discover-url "$AUTO_URL" \
      --key "$CLIENT_ID" \
      --name "Keycloak" \
      --provider "openidConnect" \
      --secret "$CLIENT_SECRET" >/dev/null 2>&1; then
      echo "Gitea auth source 'Keycloak' updated." >&2
      exit 0
    fi
  fi

  echo "Gitea OIDC config not ready yet; retrying..." >&2
  sleep 5
done

echo "Failed to configure Gitea OIDC after retries." >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.wait_for_gitea[0],
    kubectl_manifest.argocd_app_of_apps[0],
    kubernetes_secret.gitea_oidc,
  ]
}

# Force refresh app-of-apps after creation to ensure it syncs after repo-server restart
# The repo-server restart (for known_hosts update) can leave the app in Unknown state
resource "null_resource" "argocd_refresh_app_of_apps" {
  count = var.enable_gitea && (var.enable_policies || var.enable_azure_auth_sim || var.enable_llm_sentiment) ? 1 : 0

  triggers = {
    app_of_apps_id = kubectl_manifest.argocd_app_of_apps[0].id
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG=~/.kube/config
      # Wait briefly for controller to stabilize after repo-server restart
      sleep 5
      # Force refresh the app-of-apps to trigger sync
      kubectl annotate application app-of-apps -n ${var.argocd_namespace} \
        argocd.argoproj.io/refresh=normal --overwrite
      # Wait for sync to complete (up to 2 minutes)
      for i in {1..24}; do
        STATUS=$(kubectl get application app-of-apps -n ${var.argocd_namespace} -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "Synced" ]; then
          echo "app-of-apps synced successfully"
          exit 0
        fi
        echo "Waiting for app-of-apps to sync... (status: $STATUS, attempt $i/24)"
        sleep 5
      done
      echo "Error: app-of-apps did not reach Synced status within timeout"
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [kubectl_manifest.argocd_app_of_apps]
}

# -----------------------------------------------------------------------------
# In-cluster Gitea Actions Runner
# Deploys runner with host Docker socket access for building images
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "gitea_runner" {
  count = var.enable_actions_runner && !var.use_external_gitea ? 1 : 0

  metadata {
    name = "gitea-runner"
    labels = {
      "app.kubernetes.io/name"       = "gitea-actions-runner"
      "app.kubernetes.io/part-of"    = "gitea"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig
  ]
}

# Get runner registration token from in-cluster Gitea
resource "null_resource" "gitea_runner_token" {
  count = var.enable_actions_runner && !var.use_external_gitea ? 1 : 0

  triggers = {
    gitea_ready = null_resource.wait_for_gitea[0].id
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
mkdir -p "${path.module}/.run"
for i in {1..20}; do
  resp=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" -X POST \
    "${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/admin/actions/runners/registration-token" 2>/dev/null || echo '{}')
  token=$(echo "$resp" | jq -r '.token // empty')
  if [ -n "$token" ]; then
    echo -n "$token" > "${path.module}/.run/runner_reg_code"
    exit 0
  fi
  echo "Failed to get runner token, retrying... ($i/20)" >&2
  sleep 5
done
echo "Failed to obtain runner registration token" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [null_resource.wait_for_gitea]
}

data "local_file" "gitea_runner_token" {
  count      = var.enable_actions_runner && !var.use_external_gitea ? 1 : 0
  filename   = "${path.module}/.run/runner_reg_code"
  depends_on = [null_resource.gitea_runner_token]
}

# Create secret for runner registration (before ArgoCD deploys the runner)
resource "kubernetes_secret" "gitea_runner" {
  count = var.enable_actions_runner && !var.use_external_gitea ? 1 : 0

  metadata {
    name      = "act-runner-secret"
    namespace = kubernetes_namespace.gitea_runner[0].metadata[0].name
  }

  data = {
    # In-cluster Gitea URL (HTTP service in gitea namespace)
    gitea_url    = "http://gitea-http.gitea.svc.cluster.local:3000"
    runner_token = trimspace(data.local_file.gitea_runner_token[0].content)
  }

  depends_on = [
    kubernetes_namespace.gitea_runner[0],
    null_resource.gitea_runner_token[0],
    data.local_file.gitea_runner_token[0]
  ]
}

# Create repo secrets for the azure-auth-sim workflow (in-cluster registry)
resource "null_resource" "gitea_azure_auth_repo_secrets_internal" {
  count = var.enable_gitea && var.enable_actions_runner && !var.use_external_gitea ? 1 : 0

  triggers = {
    repo_id  = null_resource.gitea_create_repo_azure_auth[0].id
    password = md5(var.gitea_admin_pwd)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
create_secret() {
  local name="$1"
  local value="$2"
  for i in {1..5}; do
    status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X PUT \
      -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":\"$${value}\"}" \
      ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/azure-auth-sim/actions/secrets/$${name} || echo "000")
    if echo "$status" | grep -Eq "200|201|204"; then
      return 0
    fi
    echo "Setting secret $${name} returned HTTP $status, retrying... ($i/5)" >&2
    sleep 3
  done
  echo "Failed to create/update secret $${name}" >&2
  exit 1
}

# For in-cluster Gitea, we need two different addresses:
# 1. GITEAHOST: cluster-internal address for git clone (runs inside runner pod)
# 2. REGISTRY_HOST: Same as gitea_registry_host (e.g., localhost:30090) for docker operations
#    Docker Desktop and containerd on Kind nodes both resolve localhost to the loopback interface.
create_secret "REGISTRY_USERNAME" "${var.gitea_admin_username}"
create_secret "REGISTRY_PWD" "${var.gitea_admin_pwd}"
create_secret "REGISTRY_HOST" "${local.gitea_registry_host}"
# Note: GITEA_HOST is a reserved prefix in Gitea, so we use GITEAHOST (no underscore)
create_secret "GITEAHOST" "gitea-http.gitea.svc.cluster.local:${var.gitea_http_port_cluster}"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_create_repo_azure_auth[0],
    null_resource.wait_for_gitea[0]
  ]
}

# Create repo secrets for the sentiment-auth-ui workflow (in-cluster registry)
resource "null_resource" "gitea_sentiment_auth_repo_secrets_internal" {
  count = var.enable_gitea && var.enable_actions_runner && var.enable_sentiment_auth_frontend && !var.use_external_gitea ? 1 : 0

  triggers = {
    repo_id  = null_resource.gitea_create_repo_sentiment_auth[0].id
    password = md5(var.gitea_admin_pwd)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
create_secret() {
  local name="$1"
  local value="$2"
  for i in {1..5}; do
    status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X PUT \
      -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":\"$${value}\"}" \
      ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/sentiment-auth-ui/actions/secrets/$${name} || echo "000")
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
create_secret "REGISTRY_PWD" "${var.gitea_admin_pwd}"
create_secret "REGISTRY_HOST" "${local.gitea_registry_host}"
create_secret "GITEAHOST" "gitea-http.gitea.svc.cluster.local:${var.gitea_http_port_cluster}"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_create_repo_sentiment_auth[0],
    null_resource.wait_for_gitea[0]
  ]
}

# Create repo secrets for the sentiment-api workflow (in-cluster registry)
resource "null_resource" "gitea_sentiment_api_repo_secrets_internal" {
  count = var.enable_gitea && var.enable_actions_runner && var.enable_llm_sentiment && !var.use_external_gitea ? 1 : 0

  triggers = {
    repo_id  = null_resource.gitea_create_repo_sentiment_api[0].id
    password = md5(var.gitea_admin_pwd)
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
create_secret() {
  local name="$1"
  local value="$2"
  for i in {1..5}; do
    status=$(curl ${local.gitea_curl_insecure} -s --connect-timeout 2 --max-time 10 -o /dev/null -w "%%{http_code}" -X PUT \
      -u "${var.gitea_admin_username}:${var.gitea_admin_pwd}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":\"$${value}\"}" \
      ${local.gitea_http_scheme}://${local.gitea_http_host_local}:${local.gitea_http_port}/api/v1/repos/${var.gitea_admin_username}/sentiment-api/actions/secrets/$${name} || echo "000")
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
create_secret "REGISTRY_PWD" "${var.gitea_admin_pwd}"
create_secret "REGISTRY_HOST" "${local.gitea_registry_host}"
create_secret "GITEAHOST" "gitea-http.gitea.svc.cluster.local:${var.gitea_http_port_cluster}"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.gitea_create_repo_sentiment_api[0],
    null_resource.wait_for_gitea[0]
  ]
}

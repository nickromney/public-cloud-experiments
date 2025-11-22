ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TG ?= terragrunt
KUBECONFIG ?= $(ROOT_DIR)/.run/kubeconfig

.PHONY: plan apply destroy logs-cilium logs-hubble port-forward-hubble argocd-admin-password cilium-status ensure-run

plan: ensure-run
	cd $(ROOT_DIR) && KIND_EXPERIMENTAL_PROVIDER=podman $(TG) plan

apply: ensure-run
	cd $(ROOT_DIR) && KIND_EXPERIMENTAL_PROVIDER=podman $(TG) apply $(if $(AUTO_APPROVE),-auto-approve,)

destroy:
	cd $(ROOT_DIR) && KIND_EXPERIMENTAL_PROVIDER=podman $(TG) destroy $(if $(AUTO_APPROVE),-auto-approve,)

logs-cilium:
	KUBECONFIG=$(KUBECONFIG) kubectl -n kube-system logs -l k8s-app=cilium --tail=200 --prefix=true

logs-hubble:
	KUBECONFIG=$(KUBECONFIG) kubectl -n kube-system logs deploy/cilium-hubble-relay --tail=200 --prefix=true

port-forward-hubble:
	KUBECONFIG=$(KUBECONFIG) kubectl -n kube-system port-forward svc/hubble-ui 12000:80

argocd-admin-password:
	KUBECONFIG=$(KUBECONFIG) kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

cilium-status:
	KUBECONFIG=$(KUBECONFIG) cilium status --wait

ensure-run:
	mkdir -p $(ROOT_DIR)/.run

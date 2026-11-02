# PDE-OpenShift-Reference — task runner.
#
# Scaffold stage: targets are wired with their intended contract but most are
# stubbed (echo + TODO) until the matching build phase lands. Nothing here
# mutates a cluster yet.
#
# Usage: make help

SHELL       := /bin/bash
MODE        ?= connected    # connected | airgap
KEYCLOAK_NS ?= keycloak
.DEFAULT_GOAL := help

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'

## preflight: check required CLIs + context (oc, aws, terraform, kubeseal-free)
preflight:
	@echo "[preflight] checking tooling + cluster/AWS access..."
	@command -v oc  >/dev/null || { echo "  MISSING: oc"; exit 1; }
	@command -v aws >/dev/null || { echo "  MISSING: aws"; exit 1; }
	@echo "  TODO(P1): assert KUBECONFIG reachable, AWS account == 342934376218, base_domain set"

## deploy: one-command deploy (MODE=connected|airgap)
deploy: preflight
	@echo "[deploy MODE=$(MODE)] TODO(P1-P7): operators -> identity+SCM -> Coder -> RHOAI -> templates -> ($(MODE)=airgap: egress-deny + internal-registry-only)"

## reset: return to a clean demo state (workspaces/chats/projects), keep infra
reset:
	@echo "[reset] TODO(P7): delete demo workspaces/chats + seed projects; re-seed identity"

## mirror: populate the internal registry for air-gap (oc-mirror)
mirror:
	@echo "[mirror] TODO(P6): oc-mirror operator + workload images into the internal registry"

## status: show Argo apps + key workloads
status:
	@echo "[status] TODO(P1): oc get applications -n openshift-gitops; oc get inferenceservice -A"

## creds: print demo login credentials (personas + Keycloak admin), read live from the cluster
creds:
	@set -euo pipefail; \
	command -v oc >/dev/null || { echo "MISSING: oc"; exit 1; }; \
	oc get secret keycloak-realm-secrets -n $(KEYCLOAK_NS) >/dev/null 2>&1 || { \
	  echo "keycloak-realm-secrets not found in ns '$(KEYCLOAK_NS)' — is identity deployed?"; exit 1; }; \
	get() { oc get secret "$$1" -n $(KEYCLOAK_NS) -o jsonpath="{.data.$$2}" | base64 -d; }; \
	echo "=== Demo personas (realm: demo) ==="; \
	printf '  %-9s %-10s %s\n' USER ROLE PASSWORD; \
	printf '  %-9s %-10s %s\n' alice   developer "$$(get keycloak-realm-secrets alice_password)"; \
	printf '  %-9s %-10s %s\n' bob     auditor   "$$(get keycloak-realm-secrets bob_password)"; \
	printf '  %-9s %-10s %s\n' demoadm admin     "$$(get keycloak-realm-secrets demoadm_password)"; \
	echo; \
	echo "=== Keycloak admin console ==="; \
	kc_host=$$(oc get route keycloak -n $(KEYCLOAK_NS) -o jsonpath='{.spec.host}' 2>/dev/null || true); \
	[ -n "$$kc_host" ] && echo "  URL:      https://$$kc_host/admin" || echo "  URL:      (keycloak Route not found yet)"; \
	if oc get secret keycloak-initial-admin -n $(KEYCLOAK_NS) >/dev/null 2>&1; then \
	  printf '  %-9s %s\n' user     "$$(get keycloak-initial-admin username)"; \
	  printf '  %-9s %s\n' password "$$(get keycloak-initial-admin password)"; \
	else echo "  (keycloak-initial-admin not created yet)"; fi

## destroy: tear down the cluster + infra
destroy:
	@echo "[destroy] TODO(P1): terraform destroy (+ openshift-install destroy)"

.PHONY: help preflight deploy reset mirror status creds destroy

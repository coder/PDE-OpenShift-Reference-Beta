# PDE-OpenShift-Reference — task runner.
#
# Scaffold stage: targets are wired with their intended contract but most are
# stubbed (echo + TODO) until the matching build phase lands. Nothing here
# mutates a cluster yet.
#
# Usage: make help

SHELL := /bin/bash
MODE  ?= connected          # connected | airgap
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

## destroy: tear down the cluster + infra
destroy:
	@echo "[destroy] TODO(P1): terraform destroy (+ openshift-install destroy)"

.PHONY: help preflight deploy reset mirror status destroy

# =============================================================================
# workspace-basic — Coder workspace on OpenShift (ADR D7)
# =============================================================================
# A plain browser-dev workspace: code-server (VS Code in the browser) + optional
# Git clone from the in-cluster Gitea. No AI tooling (see workspace-agent for
# the AI-enabled variant). Runs as a restricted-v2 pod from the pre-baked
# ubi9-node-workspace image (code-server baked in -> offline start).
# =============================================================================

terraform {
  required_providers {
    coder      = { source = "coder/coder" }
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

provider "coder" {}

variable "use_kubeconfig" {
  type        = bool
  description = "Use host kubeconfig instead of in-cluster config"
  default     = false
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for workspaces"
  default     = "coder-workspaces"
}

variable "image_registry" {
  type        = string
  description = "Registry hosting the workspace images. Defaults to the OpenShift internal registry (images mirrored from GHCR via images/mirror-to-internal-registry.sh for a self-contained / air-gapped deploy)."
  default     = "image-registry.openshift-image-registry.svc:5000/coder-workspaces"
}

provider "kubernetes" {
  config_path = var.use_kubeconfig ? "~/.kube/config" : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# In-cluster Gitea external auth (optional) — the workspace boots whether or not
# the user has connected Gitea; git ops to the Gitea host then use the token
# automatically via Coder's GIT_ASKPASS helper (CODER_EXTERNAL_AUTH_0, P3).
data "coder_external_auth" "gitea" {
  id       = "gitea"
  optional = true
}

# ── Parameters ───────────────────────────────────────────────────────────────
data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "CPU limit for the workspace pod"
  type         = "number"
  default      = "2"
  mutable      = true
  icon         = "/icon/memory.svg"
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Memory limit for the workspace pod"
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "/icon/memory.svg"
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent /home/coder volume — cannot change after create"
  type         = "number"
  default      = "20"
  mutable      = false
  icon         = "/icon/database.svg"
  option {
    name  = "10 GB"
    value = "10"
  }
  option {
    name  = "20 GB"
    value = "20"
  }
  option {
    name  = "50 GB"
    value = "50"
  }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Repo to clone on start (optional; Gitea repos auth automatically)"
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/git.svg"
}

# ── Agent ────────────────────────────────────────────────────────────────────
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    #!/bin/bash
    set -e
    touch ~/.bashrc
    # User-prefixed npm globals (restricted-v2 drops CAP_SETUID, so no sudo).
    npm config set prefix "$HOME/.local" >/dev/null 2>&1 || true
    grep -qF "$HOME/.local/bin" ~/.profile 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
    echo "=== Workspace Ready ==="
  EOT

  env = {
    EDITOR              = "code"
    VISUAL              = "code"
    GITEA_HOST          = "gitea.apps.cluster.rh-pde.coderdemo.io"
    GITEA_TOKEN         = data.coder_external_auth.gitea.access_token
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory Usage"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }
}

# ── Modules ──────────────────────────────────────────────────────────────────
# code-server — runs the copy pre-baked into the image (offline; never fetches
# from code-server.dev). Copilot chat disabled (demo uses its own AI).
module "code-server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/coder/code-server/coder"
  version          = "1.6.0"
  agent_id         = coder_agent.main.id
  folder           = "/home/coder"
  subdomain        = true
  install_prefix   = "/usr/lib/code-server"
  offline          = true
  settings         = { "chat.disableAIFeatures" = true }
  machine_settings = { "chat.disableAIFeatures" = true }
  group            = "Web IDEs"
  order            = 1
}

# git-clone — only when a repo is provided.
module "git-clone" {
  count    = data.coder_parameter.git_repo.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
  base_dir = "/home/coder"
}

# dotfiles — user-provided personalization (optional; prompts for a repo URL).
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.2"
  agent_id = coder_agent.main.id
}

# ── Kubernetes resources ──────────────────────────────────────────────────────
resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources { requests = { storage = "${data.coder_parameter.disk_size.value}Gi" } }
  }
  lifecycle { ignore_changes = all }
}

resource "kubernetes_pod_v1" "workspace" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
    }
  }

  spec {
    container {
      name              = "dev"
      image             = "${var.image_registry}/ubi9-node-workspace:latest"
      image_pull_policy = "Always"
      command           = ["/usr/local/bin/uid_entrypoint", "sh", "-c", coder_agent.main.init_script]

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      env {
        name  = "CODER_AGENT_URL"
        value = data.coder_workspace.me.access_url
      }

      resources {
        requests = {
          "cpu"    = "500m"
          "memory" = "${max(2, floor(data.coder_parameter.memory.value / 2))}Gi"
        }
        limits = {
          "cpu"    = "${data.coder_parameter.cpu.value}"
          "memory" = "${data.coder_parameter.memory.value}Gi"
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
      }
    }
  }
}

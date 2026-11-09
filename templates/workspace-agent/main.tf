# =============================================================================
# workspace-agent — AI-enabled Coder workspace on OpenShift (ADR D6/D7)
# =============================================================================
# workspace-basic + offline AI CLIs (Claude Code, Codex) routed through the
# Coder AI Gateway. In the sovereign (RHOAI-only) default, the gateway's OpenAI
# provider is wired to the in-cluster vLLM Qwen2.5-7B model (Phase 4), so Codex
# talks to the local model. Claude Code's Anthropic path needs the gateway's
# Bedrock provider (connected mode) — see the NOTE on local.ai_gw_anthropic.
#
# NOTE (P7): the AI Gateway route provider names (openai vs openai-compat,
# anthropic vs bedrock) and vLLM's OpenAI API surface (Chat Completions vs the
# Responses API Codex uses) are confirmed at the fresh-cluster run; tune the
# locals/model vars below to match. The CLIs are pre-baked in the image; the
# modules only configure them.
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
  description = "Registry hosting the workspace images (default: OpenShift internal registry; see images/mirror-to-internal-registry.sh)."
  default     = "image-registry.openshift-image-registry.svc:5000/coder-workspaces"
}

# Model Codex requests through the AI Gateway OpenAI provider -> in-cluster
# vLLM (served-model-name from manifests/model-serving/serving-runtime.yaml).
variable "openai_model" {
  type        = string
  description = "Model id Codex requests via the AI Gateway OpenAI provider (in-cluster vLLM)."
  default     = "qwen2.5-7b-instruct"
}

# Model Claude Code requests via the AI Gateway Bedrock provider. Only reachable
# in connected mode (Bedrock wired on the Coder server, P4 note). Harmless if
# unused in sovereign mode.
variable "anthropic_model" {
  type        = string
  description = "Model id Claude Code requests via the AI Gateway Bedrock provider (connected mode)."
  default     = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

provider "kubernetes" {
  config_path = var.use_kubeconfig ? "~/.kube/config" : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

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
  default      = "4"
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
  default      = "8"
  mutable      = true
  icon         = "/icon/memory.svg"
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
  option {
    name  = "24 GB"
    value = "24"
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

# ── AI Gateway endpoints ──────────────────────────────────────────────────────
locals {
  # The gateway routes by provider name under /api/v2/ai-gateway/<provider>,
  # authenticated with the workspace owner's Coder session token. The OpenAI
  # provider is wired to the in-cluster vLLM (P4); the Bedrock provider is
  # connected-mode only.
  ai_gw_openai    = "${data.coder_workspace.me.access_url}/api/v2/ai-gateway/openai/v1"
  ai_gw_anthropic = "${data.coder_workspace.me.access_url}/api/v2/ai-gateway/bedrock"

  codex_base_config = <<-TOML
    model_provider = "openai-compat"
    model = "${var.openai_model}"
    model_reasoning_effort = "medium"
    sandbox_mode = "danger-full-access"
    approval_policy = "never"

    [features]
    daemon_auto_start = false

    [model_providers.openai-compat]
    name = "Coder AI Gateway (in-cluster vLLM)"
    base_url = "${local.ai_gw_openai}"
    env_key = "OPENAI_API_KEY"
    wire_api = "chat"

    [projects."/home/coder"]
    trust_level = "trusted"
  TOML
}

# ── Agent ────────────────────────────────────────────────────────────────────
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    #!/bin/bash
    set -e
    touch ~/.bashrc
    npm config set prefix "$HOME/.local" >/dev/null 2>&1 || true
    grep -qF "$HOME/.local/bin" ~/.profile 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
    # Claude Code: bypass permission prompts (demo-grade).
    mkdir -p ~/.claude
    cat > ~/.claude/settings.json <<'CLAUDESETTINGS'
    { "permissions": { "defaultMode": "bypassPermissions" }, "hasCompletedOnboarding": true }
    CLAUDESETTINGS
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
}

# ── AI Gateway auth (owner session token as the API key) ──────────────────────
resource "coder_env" "openai_base_url" {
  agent_id = coder_agent.main.id
  name     = "OPENAI_BASE_URL"
  value    = local.ai_gw_openai
}
resource "coder_env" "openai_api_key" {
  agent_id = coder_agent.main.id
  name     = "OPENAI_API_KEY"
  value    = data.coder_workspace_owner.me.session_token
}
resource "coder_env" "anthropic_base_url" {
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_BASE_URL"
  value    = local.ai_gw_anthropic
}
resource "coder_env" "anthropic_api_key" {
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_API_KEY"
  value    = data.coder_workspace_owner.me.session_token
}

# ── Modules ──────────────────────────────────────────────────────────────────
module "code-server" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/code-server/coder"
  version        = "1.3.1"
  agent_id       = coder_agent.main.id
  folder         = "/home/coder"
  subdomain      = true
  install_prefix = "/usr/lib/code-server"
  offline        = true
  settings         = { "chat.disableAIFeatures" = true }
  machine-settings = { "chat.disableAIFeatures" = true }
  group = "Web IDEs"
  order = 1
}

module "claude-code" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.4.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder"
  model    = var.anthropic_model
}

module "codex" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/coder-labs/codex/coder"
  version          = "5.3.2"
  agent_id         = coder_agent.main.id
  workdir          = "/home/coder"
  install_codex    = true
  base_config_toml = local.codex_base_config
}

module "git-clone" {
  count    = data.coder_parameter.git_repo.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "1.0.22"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
  base_dir = "/home/coder"
}

module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
}

# ── AI CLI launchers ──────────────────────────────────────────────────────────
resource "coder_app" "claude_code" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  group        = "AI Tools"
  order        = 5
  open_in      = "slim-window"
  command      = <<-EOT
    cd "$HOME"
    claude --dangerously-skip-permissions
  EOT
}

resource "coder_app" "codex" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "codex"
  display_name = "Codex"
  icon         = "/icon/openai.svg"
  group        = "AI Tools"
  order        = 6
  open_in      = "slim-window"
  command      = <<-EOT
    cd "$HOME"
    codex
  EOT
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
          "cpu"    = "1"
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

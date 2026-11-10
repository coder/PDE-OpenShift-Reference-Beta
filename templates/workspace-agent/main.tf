# =============================================================================
# workspace-agent — AI-enabled Coder workspace on OpenShift (ADR D6/D7)
# =============================================================================
# workspace-basic + AI CLIs (Claude Code, Codex) routed through the Coder AI
# Gateway with the owner's session token (providers: `task ai-provider`):
#     Codex       -> provider `openai`  (in-cluster RHOAI vLLM, Qwen2.5-7B)
#     Claude Code -> provider `bedrock` (AWS Bedrock; connected mode only)
# =============================================================================

terraform {
  required_providers {
    # Pinned below 2.20: 2.20.0 deprecates data.coder_task, which the
    # claude-code/codex modules still declare via coder-utils (warning only).
    coder      = { source = "coder/coder", version = "~> 2.19.0" }
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

# Model Claude Code requests via the AI Gateway Bedrock provider (connected
# mode). Must be one of the provider's models (ai-providers/configure.py):
# the gateway silently rewrites unknown model ids to the provider default.
variable "anthropic_model" {
  type        = string
  description = "Model id Claude Code requests via the AI Gateway Bedrock provider (connected mode)."
  default     = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
}

# Models offered in Claude Code's /model picker (the Bedrock provider's models).
variable "anthropic_available_models" {
  type        = list(string)
  description = "Model ids Claude Code may select (locked picker)."
  default = [
    "global.anthropic.claude-haiku-4-5-20251001-v1:0",
    "global.anthropic.claude-opus-4-5-20251101-v1:0",
  ]
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

  claude_settings = jsonencode({
    permissions                       = { defaultMode = "bypassPermissions" }
    skipDangerousModePermissionPrompt = true
    hasCompletedOnboarding            = true
    hasAcknowledgedCostThreshold      = true
    availableModels                   = var.anthropic_available_models
  })

  # Codex config.toml, written verbatim by the codex module.
  #   * wire_api = "responses": Codex >= 0.167 dropped "chat".
  #   * web_search = "disabled": the hosted web_search tool isn't served by
  #     vLLM (or Bedrock's OpenAI endpoint).
  #   * sandbox_mode = "danger-full-access": the pod is the sandbox (no bwrap).
  codex_base_config = <<-TOML
    model_provider = "openai-compat"
    model = "${var.openai_model}"
    model_reasoning_effort = "medium"
    web_search = "disabled"
    sandbox_mode = "danger-full-access"
    approval_policy = "never"

    [features]
    daemon_auto_start = false

    [model_providers.openai-compat]
    name = "Coder AI Gateway (in-cluster vLLM)"
    base_url = "${local.ai_gw_openai}"
    env_key = "OPENAI_API_KEY"
    wire_api = "responses"

    [projects."/home/coder"]
    trust_level = "trusted"
  TOML
}

# ── Agent ────────────────────────────────────────────────────────────────────
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # No `set -e`: a non-critical step must not fail the whole agent startup.
  startup_script = <<-EOT
    #!/bin/bash
    touch ~/.bashrc
    npm config set prefix "$HOME/.local" >/dev/null 2>&1 || true

    # PATH for ~/.local/bin + the npm global bin (where the modules install the CLIs)
    NPM_BIN="$(npm config get prefix 2>/dev/null)/bin"
    for P in "$HOME/.local/bin" "$NPM_BIN"; do
      grep -qF "$P" ~/.profile 2>/dev/null || echo "export PATH=\"$P:\$PATH\"" >> ~/.profile
    done

    # Claude Code user settings: bypass permission prompts (demo-grade) and LOCK
    # the model picker to the gateway's Bedrock models. The claude-code module
    # writes its install state to ~/.claude.json (a different file).
    mkdir -p ~/.claude
    cat > ~/.claude/settings.json <<'CLAUDESETTINGS'
    ${local.claude_settings}
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

    # No docker socket in the pod: opt out of devcontainer detection, which
    # otherwise stalls dashboard polls on `docker ps`.
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
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

  display_apps {
    vscode                 = true
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
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
  version        = "1.6.0"
  agent_id       = coder_agent.main.id
  folder         = "/home/coder"
  subdomain      = true
  install_prefix = "/usr/lib/code-server"
  offline        = true
  # Copilot chat is baked into code-server core; chat.disableAIFeatures is the
  # kill-switch, and extensions.allowed blocks side-loaded Copilot extensions.
  settings = { "chat.disableAIFeatures" = true }
  machine_settings = {
    "chat.disableAIFeatures" = true
    "extensions.allowed" = {
      "*"                   = true
      "github.copilot"      = false
      "github.copilot-chat" = false
    }
  }
  group = "Web IDEs"
  order = 1
}

module "claude-code" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.5.2"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder"
  model    = var.anthropic_model
}

# Pre-approve ANTHROPIC_API_KEY so Claude Code never asks "Detected a custom
# API key ... use this API key?". Claude Code matches the key's last 20 chars
# in ~/.claude.json customApiKeyResponses.approved; the key (the owner's
# session token) rotates every start, so this runs on_start. Backgrounded and
# logged to a file so it never blocks or fails workspace startup.
resource "coder_script" "claude_approve_key" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Claude Code: pre-approve API key"
  icon         = "/icon/claude.svg"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    (
      set -u
      CFG="$HOME/.claude.json"
      # Wait for the claude-code module to finish writing ~/.claude.json.
      for _ in $(seq 1 60); do
        [ -f "$CFG" ] && jq -e '.hasCompletedOnboarding == true' "$CFG" >/dev/null 2>&1 && break
        sleep 2
      done
      [ -f "$CFG" ] || echo '{}' > "$CFG"
      KEY="$${ANTHROPIC_API_KEY:-}"
      [ -n "$KEY" ] || exit 0
      SUFFIX=$(printf %s "$KEY" | tail -c 20)
      tmp=$(mktemp)
      jq --arg k "$SUFFIX" '.customApiKeyResponses = (.customApiKeyResponses // {"approved":[],"rejected":[]}) | .customApiKeyResponses.approved = (((.customApiKeyResponses.approved // []) + [$k]) | unique) | .customApiKeyResponses.rejected = ((.customApiKeyResponses.rejected // []) - [$k])' "$CFG" > "$tmp" 2>/dev/null \
        && mv "$tmp" "$CFG" && echo "Pre-approved ANTHROPIC_API_KEY." \
        || rm -f "$tmp"
    ) >/tmp/claude-approve-key.log 2>&1 &
    disown 2>/dev/null || true
    exit 0
  EOT
}

module "codex" {
  count         = data.coder_workspace.me.start_count
  source        = "registry.coder.com/coder-labs/codex/coder"
  version       = "5.5.0"
  agent_id      = coder_agent.main.id
  workdir       = "/home/coder"
  install_codex = true
  # Pinned: 0.167.0 is verified against the gateway + vLLM Responses API.
  # Unpinned ("latest") broke startup once when Codex dropped wire_api=chat.
  codex_version    = "0.167.0"
  base_config_toml = local.codex_base_config
}

module "git-clone" {
  count    = data.coder_parameter.git_repo.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
  base_dir = "/home/coder"
}

module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.2"
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
    codex --no-daemon
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

    # Spread workspaces across nodes.
    affinity {
      pod_anti_affinity {
        preferred_during_scheduling_ignored_during_execution {
          weight = 1
          pod_affinity_term {
            topology_key = "kubernetes.io/hostname"
            label_selector {
              match_expressions {
                key      = "app.kubernetes.io/name"
                operator = "In"
                values   = ["coder-workspace"]
              }
            }
          }
        }
      }
    }
  }
}

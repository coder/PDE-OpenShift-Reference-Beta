# workspace-agent

`workspace-basic` plus **Claude Code** and **Codex**, both routed through the
Coder **AI Gateway** (ADR D6/D7). Providers and models are created on the Coder
server by `task ai-provider` (see [`ai-providers/`](../../ai-providers/)).

| CLI | Gateway route | Backend | Default model |
|-----|---------------|---------|---------------|
| Codex | `/api/v2/ai-gateway/openai/v1` (provider `openai`) | in-cluster RHOAI vLLM | `qwen2.5-7b-instruct` (`openai_model`) |
| Claude Code | `/api/v2/ai-gateway/bedrock` (provider `bedrock`) | AWS Bedrock via IRSA (connected mode only) | Claude Haiku 4.5 (`anthropic_model`); `/model` picker limited to Haiku 4.5 + Opus 4.5 |

- **Auth:** the workspace owner's Coder session token is exported as
  `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`. A `run_on_start` script
  (`claude_approve_key`) pre-approves that key in `~/.claude.json`, so Claude
  Code never shows its "use this API key?" prompt. The token rotates on every
  start, which is why the script runs each time.
- **Install:** the CLIs are **not** in the image. The pinned registry modules
  download and install them on every workspace start, so a workspace needs
  egress for this (see the
  [air-gap gaps](../../docs/air-gap.md#known-gaps)).
- **Codex config:** `wire_api = "responses"` (Codex ≥ 0.167 dropped Chat
  Completions; vLLM serves the Responses API through the gateway), and
  `web_search = "disabled"` because vLLM doesn't serve the hosted tool. The
  Codex app launches `codex --no-daemon`.
- **Model ids matter:** `anthropic_model` must be one of the Bedrock provider's
  models. The gateway silently rewrites unknown ids to the provider default.

## Pins (verified live 2026-11-10)
| Item | Version | Why |
|------|---------|-----|
| `coder/coder` provider | `~> 2.19.0` | 2.20 deprecates `data.coder_task`, which the modules still declare (warning only) |
| `claude-code` module | 5.5.2 | |
| `codex` module / `codex_version` | 5.5.0 / **0.167.0** | unpinned "latest" broke startup once when Codex dropped `wire_api=chat` |
| `code-server` / `git-clone` / `dotfiles` | 1.6.0 / 2.0.5 / 1.4.2 | |

## Push
```bash
task push-templates      # preferred: sets image_registry + anthropic_model
```
Use `task push-templates` rather than a bare `coder templates push`. A push
reuses the previous version's variable values, so a stale `anthropic_model`
would otherwise carry over.

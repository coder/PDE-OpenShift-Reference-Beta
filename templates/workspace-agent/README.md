# workspace-agent

`workspace-basic` plus offline **AI CLIs** — **Claude Code** and **Codex** —
routed through the Coder **AI Gateway** (ADR D6/D7).

- **Sovereign default:** the gateway's OpenAI provider is wired (Phase 4) to the
  in-cluster **vLLM Qwen2.5-7B** model, so Codex talks to the local model —
  no egress needed.
- **Connected option:** Claude Code's Anthropic path uses the gateway's Bedrock
  provider (requires Bedrock wired on the Coder server).
- Auth to the gateway is the workspace owner's Coder session token
  (`OPENAI_API_KEY`/`ANTHROPIC_API_KEY`); the CLIs are pre-baked in the image,
  the registry modules only configure them.

```bash
coder templates push workspace-agent -d ./templates/workspace-agent
```

**P7 tuning:** AI-Gateway provider route names (`openai` vs `openai-compat`,
`anthropic` vs `bedrock`) and vLLM's OpenAI API surface (Chat Completions vs
Responses) are confirmed at the fresh-cluster run — adjust the `locals`/model
vars in `main.tf` to match.

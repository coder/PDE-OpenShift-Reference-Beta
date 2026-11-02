# templates/
Coder workspace templates (Terraform). Two (D7):
- `workspace-basic` — a governed dev workspace (internal-registry image).
- `workspace-agent` — adds offline AI CLIs (claude-code / codex) baked into the image
  for Coder Agents; an egress-controlled flavor is enabled in air-gap mode.
Ported/simplified from the prior build's proven offline-CLI + code-server bake.

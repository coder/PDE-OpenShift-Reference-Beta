#!/usr/bin/env python3
"""Idempotently configure Coder AI Gateway providers + Coder Agents models.

Coder 2.39 keeps AI providers and Agents models in the database only (the old
CODER_AI_GATEWAY_* provider env vars are ignored), so they are configured
through the Coder API after `coder login` + license. Run via `task ai-provider`.

Providers (routed by NAME at /api/v2/ai-gateway/<name>):
  openai   in-cluster vLLM (RHOAI)  -> Codex, always
  bedrock  AWS Bedrock (Anthropic)  -> Claude Code, only when BEDROCK_ENABLE=1.
           Credentials come from the coder-server pod's IRSA role (coder SA
           annotation, `task coder-irsa`) -- no static keys.

Agents models (org-scoped chat models): Qwen on vLLM, plus Opus/Haiku on
Bedrock. The default is the Bedrock primary model when enabled, else Qwen.

Environment (the Taskfile sets these; secrets are never printed):
  AIP_CODER_URL, AIP_CODER_TOKEN          Coder URL + owner session token
  VLLM_BASE_URL, VLLM_MODEL, VLLM_CONTEXT_LIMIT
  BEDROCK_ENABLE (0|1), BEDROCK_REGION, BEDROCK_MODEL, BEDROCK_SMALL_FAST_MODEL
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ["AIP_CODER_URL"].rstrip("/")
TOKEN = os.environ["AIP_CODER_TOKEN"]

VLLM_BASE_URL = os.environ["VLLM_BASE_URL"]
VLLM_MODEL = os.environ.get("VLLM_MODEL", "qwen2.5-7b-instruct")
VLLM_CONTEXT_LIMIT = int(os.environ.get("VLLM_CONTEXT_LIMIT", "16384"))

BEDROCK_ENABLE = os.environ.get("BEDROCK_ENABLE", "0") == "1"
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")
BEDROCK_MODEL = os.environ.get(
    "BEDROCK_MODEL", "global.anthropic.claude-opus-4-5-20251101-v1:0")
BEDROCK_SMALL_FAST_MODEL = os.environ.get(
    "BEDROCK_SMALL_FAST_MODEL", "global.anthropic.claude-haiku-4-5-20251001-v1:0")


class APIError(Exception):
    pass


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header("Coder-Session-Token", TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"message": raw.decode(errors="replace")}


def must(method, path, body=None, ok=(200, 201)):
    code, out = api(method, path, body)
    if code not in ok:
        msg = (out or {}).get("message", "")
        detail = (out or {}).get("detail", "")
        vals = (out or {}).get("validations") or ""
        raise APIError(f"{method} {path}: HTTP {code} {msg} {detail} {vals}".strip())
    return out


def ensure_provider(name, create, patch):
    code, cur = api("GET", f"/api/v2/ai/providers/{name}")
    if code == 200:
        changed = {k: v for k, v in patch.items() if cur.get(k) != v}
        if changed:
            cur = must("PATCH", f"/api/v2/ai/providers/{name}", patch)
            print(f"[ai-provider] provider {name}: updated ({', '.join(changed)})")
        else:
            print(f"[ai-provider] provider {name}: up to date")
        return cur["id"]
    out = must("POST", "/api/v2/ai/providers", create)
    print(f"[ai-provider] provider {name}: created")
    return out["id"]


def ensure_model(org, existing, provider_id, model, display, context_limit,
                 model_config, is_default):
    want = {
        "display_name": display,
        "enabled": True,
        "context_limit": context_limit,
        "model_config": model_config,
    }
    for m in existing:
        if m["ai_provider_id"] == provider_id and m["model"] == model:
            patch = {k: v for k, v in want.items() if m.get(k) != v}
            if is_default and not m.get("is_default"):
                patch["is_default"] = True
            if patch:
                must("PATCH", f"/api/v2/organizations/{org}/chats/models/{m['id']}", patch)
                print(f"[ai-provider] model {display}: updated ({', '.join(patch)})")
            else:
                print(f"[ai-provider] model {display}: up to date")
            return
    body = dict(want, ai_provider_id=provider_id, model=model, is_default=is_default)
    must("POST", f"/api/v2/organizations/{org}/chats/models", body)
    print(f"[ai-provider] model {display}: created{' (default)' if is_default else ''}")


def main():
    ents = must("GET", "/api/v2/entitlements")
    if not ents.get("has_license") or \
            ents.get("features", {}).get("aibridge", {}).get("entitlement") != "entitled":
        raise APIError("no active license with AI Gateway "
                       f"(errors: {ents.get('errors') or 'none'}); "
                       "run: coder licenses add -f <license.jwt>")

    org = must("GET", "/api/v2/users/me")["organization_ids"][0]

    # vLLM runs without auth in-cluster; the key is a non-secret placeholder.
    vllm_id = ensure_provider(
        "openai",
        create={"type": "openai", "name": "openai",
                "display_name": "In-cluster vLLM (Qwen2.5-7B)", "enabled": True,
                "base_url": VLLM_BASE_URL, "api_keys": ["unused-local-vllm"]},
        patch={"enabled": True, "base_url": VLLM_BASE_URL},
    )

    bedrock_id = None
    if BEDROCK_ENABLE:
        settings = {"_type": "bedrock", "_version": 1, "region": BEDROCK_REGION,
                    "model": BEDROCK_MODEL, "small_fast_model": BEDROCK_SMALL_FAST_MODEL}
        base_url = f"https://bedrock-runtime.{BEDROCK_REGION}.amazonaws.com"
        bedrock_id = ensure_provider(
            "bedrock",
            create={"type": "bedrock", "name": "bedrock", "display_name": "AWS Bedrock",
                    "enabled": True, "base_url": base_url, "settings": settings},
            patch={"enabled": True, "base_url": base_url, "settings": settings},
        )
    else:
        print("[ai-provider] bedrock: skipped (no Coder IRSA role; sovereign/RHOAI-only)")

    existing = must("GET", f"/api/v2/organizations/{org}/chats/models").get("models") or []
    anthropic_opts = {"provider_options": {"anthropic": {"send_reasoning": True}}}
    if bedrock_id:
        ensure_model(org, existing, bedrock_id, BEDROCK_MODEL, "Claude Opus 4.5",
                     200000, dict(max_output_tokens=64000, **anthropic_opts), True)
        ensure_model(org, existing, bedrock_id, BEDROCK_SMALL_FAST_MODEL, "Claude Haiku 4.5",
                     200000, dict(max_output_tokens=64000, **anthropic_opts), False)
    # Hermes tool calling is enabled on the vLLM runtime, so the Agents
    # tool-calling loop works against Qwen; cap output well under the 16K context.
    ensure_model(org, existing, vllm_id, VLLM_MODEL, "Qwen2.5 7B Instruct (RHOAI vLLM)",
                 VLLM_CONTEXT_LIMIT, {"max_output_tokens": 4096}, bedrock_id is None)

    print(f"[ai-provider] ok. Gateway routes: {URL}/api/v2/ai-gateway/openai/v1"
          + (f", {URL}/api/v2/ai-gateway/bedrock" if bedrock_id else ""))


if __name__ == "__main__":
    try:
        main()
    except APIError as e:
        print(f"[ai-provider] ERROR: {e}", file=sys.stderr)
        sys.exit(1)

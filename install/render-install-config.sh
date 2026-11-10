#!/bin/sh
# Render an openshift-install install-config.yaml from the committed example
# (or your own copy) plus a pull secret and SSH public key read from FILES, so
# secret values are never typed on a command line or written into git (D5).
#
#   ./install/render-install-config.sh \
#     --pull-secret ~/pde-deploy/secrets/pull-secret.json \
#     --ssh-key     ~/pde-deploy/secrets/id_ed25519.pub \
#     --out-dir     ~/pde-deploy/cluster \
#     [--template   install/install-config.yaml.example]
#
# Writes <out-dir>/install-config.yaml (mode 0600) and a backup copy
# <out-dir>/install-config.yaml.bak, because `openshift-install create
# manifests` consumes (deletes) the original. Keep <out-dir> OUTSIDE the git
# checkout; the script refuses to write inside one.
set -eu

die() { printf '[render] ERROR: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

TEMPLATE=$(cd "$(dirname "$0")" && pwd)/install-config.yaml.example
PS=""; KEY=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pull-secret) PS=$2; shift 2 ;;
    --ssh-key)     KEY=$2; shift 2 ;;
    --out-dir)     OUT=$2; shift 2 ;;
    --template)    TEMPLATE=$2; shift 2 ;;
    -h|--help)     usage 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage 1 ;;
  esac
done
[ -n "$PS" ] && [ -n "$KEY" ] && [ -n "$OUT" ] || usage 1
for c in jq python3; do command -v "$c" >/dev/null || die "missing prerequisite: $c"; done

[ -s "$TEMPLATE" ] || die "template not found: $TEMPLATE"
[ -s "$PS" ] || die "pull secret not found or empty: $PS"
jq -e '.auths["registry.redhat.io"]' "$PS" >/dev/null 2>&1 \
  || die "pull secret is not valid JSON or lacks registry.redhat.io"
jq -c . "$PS" | grep -q "'" && die "pull secret contains a single quote; cannot embed safely"
[ -s "$KEY" ] || die "SSH public key not found or empty: $KEY"
grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2-[a-z0-9]+) ' "$KEY" \
  || die "$KEY does not look like an SSH PUBLIC key (pass the .pub file)"
grep -q '<RED_HAT_PULL_SECRET_JSON>' "$TEMPLATE" && grep -q '<SSH_PUBLIC_KEY>' "$TEMPLATE" \
  || die "template must contain the <RED_HAT_PULL_SECRET_JSON> and <SSH_PUBLIC_KEY> placeholders"

# Refuse a target inside a git checkout (check the nearest existing ancestor
# before creating anything).
P=$OUT; while [ ! -d "$P" ]; do P=$(dirname "$P"); done
if command -v git >/dev/null && git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "$OUT is inside a git work tree; choose a directory outside the repo"
fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

umask 077
PS_JSON=$(jq -c . "$PS") SSH_KEY=$(head -1 "$KEY") \
python3 - "$TEMPLATE" "$OUT/install-config.yaml" <<'EOF'
import os, sys
t = open(sys.argv[1]).read()
t = t.replace("<RED_HAT_PULL_SECRET_JSON>", os.environ["PS_JSON"]).replace("<SSH_PUBLIC_KEY>", os.environ["SSH_KEY"].strip())
open(sys.argv[2], "w").write(t)
EOF
cp "$OUT/install-config.yaml" "$OUT/install-config.yaml.bak"
printf '[render] wrote %s (+ .bak). Edit zones/instance types there if needed, then:\n' "$OUT/install-config.yaml"
printf '         openshift-install create manifests --dir %s\n' "$OUT"

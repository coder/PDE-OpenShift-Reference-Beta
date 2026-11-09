# ubi9-node-workspace — Node 22 + pre-baked code-server on ubi9-base-workspace.
#
# The image the Coder templates use (workspace-basic, workspace-agent). Node +
# code-server are baked so workspaces start OFFLINE (no download from
# code-server.dev) — air-gap posture + no flaky-download startup failures.
#
# Pushed to GHCR by .github/workflows/build-images.yml. Tag scheme:
#   ghcr.io/coder/pde-openshift-reference/ubi9-node-workspace:{9.7,latest}
ARG WORKSPACE_BASE=ghcr.io/coder/pde-openshift-reference/ubi9-base-workspace:latest
FROM ${WORKSPACE_BASE}

USER 0

# Node.js 22 LTS via NodeSource (UBI9 default repos ship only Node 18);
# yarn + pnpm via corepack. typescript as a common global.
RUN curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - \
    && dnf install -y --nodocs --setopt=install_weak_deps=False nodejs \
    && dnf clean all && rm -rf /var/cache/dnf \
    && corepack enable yarn pnpm \
    && npm install --global --no-fund --no-audit typescript \
    && rm -rf /root/.npm

# code-server pre-baked to a fixed read-only prefix. The coder/code-server
# module is configured offline=true, install_prefix=/usr/lib/code-server so it
# runs THIS copy and never fetches from the internet.
ARG CODE_SERVER_VERSION=4.144.0
RUN curl -fsSL https://code-server.dev/install.sh \
      | sh -s -- --method=standalone --prefix=/usr/lib/code-server --version="${CODE_SERVER_VERSION}" \
    && chmod -R a+rX /usr/lib/code-server \
    && /usr/lib/code-server/bin/code-server --version

# Unlink GitHub Copilot from VS Code CORE (product.json defaultChatAgent) so the
# built-in Copilot chat panel does not surface (belt-and-suspenders with the
# templates' chat.disableAIFeatures=true user setting).
RUN PJ="$(find /usr/lib/code-server -name product.json -path '*/vscode/*' | head -1)" \
    && test -n "$PJ" \
    && jq 'del(.defaultChatAgent)' "$PJ" > "$PJ.tmp" && mv "$PJ.tmp" "$PJ" \
    && echo "Removed defaultChatAgent from $PJ"

# Re-apply OCP-friendly home perms after root installs.
RUN chgrp -R 0 /home/coder && chmod -R g=u /home/coder

USER 1001
WORKDIR /home/coder
CMD ["sleep", "infinity"]

# ubi9-base-workspace — UBI 9.7 + dev tooling for Coder workspaces on OpenShift.
#
# Base image for ubi9-node-workspace (the image the templates actually use).
# Built on UBI9 for a "RHEL inside OpenShift" posture and controlled security.
#
# OpenShift restricted-v2 SCC: at runtime OCP injects a random non-root UID, so
# the image USER is overridden. The Red Hat pattern is to make HOME and
# /etc/passwd group-writable by GID 0 (added as a supplemental group to every
# restricted pod) so the injected UID can read/write; a uid_entrypoint adds a
# passwd entry for that UID at startup (the Coder agent needs os/user.Current()).
#
# Pushed to GHCR by .github/workflows/build-images.yml. Tag scheme:
#   ghcr.io/coder/pde-openshift-reference/ubi9-base-workspace:{9.7,latest}
FROM registry.access.redhat.com/ubi9/ubi:9.7

ARG USER=coder
ARG UID=1001

# bash + pipefail so piped RUNs (curl | sh) fail on upstream errors (DL4006).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# EPEL (fzf/ripgrep/fd-find live there), as its own layer; the next dnf
# install refreshes metadata automatically.
RUN dnf install -y --nodocs --setopt=install_weak_deps=False \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && dnf clean all && rm -rf /var/cache/dnf

# Core dev tooling + dotfiles deps. Pre-baked because restricted-v2 drops
# CAP_SETUID, so `sudo dnf install` from a startup script can't elevate.
# (curl omitted — UBI9 ships curl-minimal which conflicts with full curl.)
# RPM versions are intentionally not pinned (DL3041): Red Hat ships rolling
# z-stream within a minor, so we pin the UBI MINOR (ubi:9.7) instead.
# hadolint ignore=DL3041
RUN dnf install -y --nodocs --setopt=install_weak_deps=False \
        bash-completion ca-certificates fd-find fzf gcc git gnupg2 jq less make \
        neovim openssh-clients procps-ng python3.11 python3.11-pip ripgrep sudo \
        tar unzip vim-enhanced wget which zip zsh \
    && dnf clean all && rm -rf /var/cache/dnf

# tmux — not in UBI9/EPEL; pull the Rocky 9 BaseOS RPM (same source as RHEL 9).
RUN dnf install -y --nodocs \
        https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/Packages/t/tmux-3.2a-5.el9.x86_64.rpm \
    && dnf clean all && rm -rf /var/cache/dnf

# Starship prompt (dotfiles use it). Installed at build time as root.
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin

RUN useradd --uid ${UID} --create-home --shell /bin/bash --user-group ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER}

# OpenShift-friendly perms: GID 0 group-writable HOME + /etc/passwd.
RUN chgrp -R 0 /home/${USER} && chmod -R g=u /home/${USER} \
    && chmod g=u /etc/passwd

COPY uid_entrypoint.sh /usr/local/bin/uid_entrypoint
RUN chmod 0755 /usr/local/bin/uid_entrypoint

# $SHELL set so dotfiles install.sh skips `sudo chsh` (blocked under restricted-v2).
ENV SHELL=/usr/bin/zsh

ENTRYPOINT ["/usr/local/bin/uid_entrypoint"]
USER ${UID}
WORKDIR /home/${USER}
CMD ["sleep", "infinity"]

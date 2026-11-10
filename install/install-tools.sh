#!/bin/sh
# Install the CLIs this repo's runbook uses into a user prefix (no root needed
# except, on some distros, for the oc-mirror library workaround below).
#
#   ./install/install-tools.sh                     # installs into ~/.local/bin
#   OCP_VERSION=4.21.42 PREFIX=$HOME/.local ./install/install-tools.sh
#   FORCE=1 ./install/install-tools.sh             # reinstall everything
#
# Installs (if missing): oc, openshift-install, ccoctl, oc-mirror (pinned to
# OCP_VERSION), AWS CLI v2, go-task, terraform, jq. Checks for: curl, tar,
# unzip, python3. Idempotent; safe to re-run (e.g. after a Coder workspace
# restart, which wipes /usr/local and /opt but keeps $HOME).
# Supported: Linux x86_64.
set -eu

OCP_VERSION=${OCP_VERSION:-4.21.42}
TF_VERSION=${TF_VERSION:-1.17.1}
JQ_VERSION=${JQ_VERSION:-1.8.1}
PREFIX=${PREFIX:-$HOME/.local}
FORCE=${FORCE:-0}
PATH_ORIG=$PATH
BIN=$PREFIX/bin
OCM_LIB=$PREFIX/lib/oc-mirror
OCP_MIRROR=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$OCP_VERSION
UBI_PKGS=https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi9/9/x86_64/baseos/os/Packages

log() { printf '[tools] %s\n' "$*"; }
die() { printf '[tools] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] \
  || die "only Linux x86_64 is supported (got $(uname -s) $(uname -m))"
for c in curl tar unzip; do command -v "$c" >/dev/null || die "missing prerequisite: $c"; done
command -v python3 >/dev/null || log "WARN: python3 not found (needed by task ai-provider)"

mkdir -p "$BIN" "$OCM_LIB"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

need() { [ "$FORCE" = 1 ] || [ ! -x "$BIN/$1" ]; }

# oc / openshift-install / ccoctl: tarball containing the named binary.
ocp_tool() {  # $1 tarball name, $2 binary
  if need "$2"; then
    log "installing $2 $OCP_VERSION"
    curl -sfL "$OCP_MIRROR/$1" | tar xz -C "$T" "$2" || die "download failed: $OCP_MIRROR/$1"
    install -m 0755 "$T/$2" "$BIN/$2"
  else log "$2 present"; fi
}
ocp_tool "openshift-client-linux-$OCP_VERSION.tar.gz" oc
ocp_tool "openshift-install-linux-$OCP_VERSION.tar.gz" openshift-install
ocp_tool "ccoctl-linux-$OCP_VERSION.tar.gz" ccoctl

# oc-mirror: the RHEL9 build. It links libgpgme.so.11 + libassuan.so.0; distros
# without them (e.g. recent Ubuntu) get the UBI9 copies in $OCM_LIB and a
# wrapper that sets LD_LIBRARY_PATH. On RHEL/Fedora the wrapper is a no-op.
if [ "$FORCE" = 1 ] || [ ! -x "$OCM_LIB/oc-mirror" ]; then
  log "installing oc-mirror $OCP_VERSION"
  curl -sfL "$OCP_MIRROR/oc-mirror.rhel9.tar.gz" | tar xz -C "$T" oc-mirror || die "oc-mirror download failed"
  install -m 0755 "$T/oc-mirror" "$OCM_LIB/oc-mirror"
fi
missing_libs() { LD_LIBRARY_PATH=$OCM_LIB ldd "$OCM_LIB/oc-mirror" 2>/dev/null | grep -E 'lib(gpgme|assuan)' | grep 'not found' || true; }
if [ -n "$(missing_libs)" ]; then
  log "oc-mirror needs libgpgme/libassuan; fetching them from UBI9"
  ubi_rpm() {  # $1 subdir, $2 package-name regex -> newest matching rpm filename
    curl -sfL "$UBI_PKGS/$1/" | grep -oE "$2-[0-9][^\"]*\.el9[^\"]*\.x86_64\.rpm" | sort -uV | tail -1
  }
  G=$(ubi_rpm g gpgme); A=$(ubi_rpm l libassuan)
  [ -n "$G" ] && [ -n "$A" ] || die "could not find gpgme/libassuan RPMs under $UBI_PKGS"
  ( cd "$T" && curl -sfLO "$UBI_PKGS/g/$G" && curl -sfLO "$UBI_PKGS/l/$A" )
  if command -v bsdtar >/dev/null; then x() { bsdtar -xf "$1"; }
  elif command -v rpm2cpio >/dev/null && command -v cpio >/dev/null; then x() { rpm2cpio "$1" | cpio -idm --quiet; }
  elif command -v apt-get >/dev/null && command -v sudo >/dev/null; then
    log "installing libarchive-tools (bsdtar) via apt-get"
    sudo apt-get update -qq && sudo apt-get install -y -qq libarchive-tools >/dev/null
    x() { bsdtar -xf "$1"; }
  else die "need bsdtar or rpm2cpio+cpio to unpack $G / $A"; fi
  ( cd "$T" && x "$G" && x "$A" )
  cp -a "$T"/usr/lib64/libgpgme.so.11* "$T"/usr/lib64/libassuan.so.0* "$OCM_LIB/"
  [ -z "$(missing_libs)" ] || die "oc-mirror still has unresolved libraries: $(missing_libs)"
fi
cat > "$BIN/oc-mirror" <<EOF
#!/bin/sh
LD_LIBRARY_PATH=$OCM_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH} exec $OCM_LIB/oc-mirror "\$@"
EOF
chmod 0755 "$BIN/oc-mirror"

# AWS CLI v2
if need aws; then
  log "installing AWS CLI v2"
  curl -sfL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$T/awscli.zip"
  ( cd "$T" && unzip -q awscli.zip && ./aws/install -i "$PREFIX/aws-cli" -b "$BIN" --update >/dev/null )
else log "aws present"; fi

# go-task
if need task; then
  log "installing go-task"
  sh -c "$(curl -sfL https://taskfile.dev/install.sh)" -- -b "$BIN" >/dev/null 2>&1 || die "go-task install failed"
else log "task present"; fi

# terraform / jq: only when not already on PATH (e.g. provided by the image).
if [ "$FORCE" = 1 ] || ! command -v terraform >/dev/null; then
  log "installing terraform $TF_VERSION"
  curl -sfL "https://releases.hashicorp.com/terraform/$TF_VERSION/terraform_${TF_VERSION}_linux_amd64.zip" -o "$T/tf.zip"
  ( cd "$T" && unzip -qo tf.zip terraform ) && install -m 0755 "$T/terraform" "$BIN/terraform"
else log "terraform present ($(command -v terraform))"; fi
if [ "$FORCE" = 1 ] || ! command -v jq >/dev/null; then
  log "installing jq $JQ_VERSION"
  curl -sfL "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-amd64" -o "$T/jq"
  install -m 0755 "$T/jq" "$BIN/jq"
else log "jq present ($(command -v jq))"; fi

log "done. Versions:"
PATH=$BIN:$PATH
printf '  %-18s %s\n' oc "$(oc version --client 2>/dev/null | head -1)" \
  openshift-install "$(openshift-install version 2>/dev/null | head -1)" \
  oc-mirror "$(oc-mirror version --output=yaml 2>/dev/null | awk '/gitVersion/{print $2; exit}')" \
  aws "$(aws --version 2>&1)" task "$(task --version 2>/dev/null)" \
  terraform "$(terraform version 2>/dev/null | head -1)" jq "$(jq --version 2>/dev/null)"
case ":$PATH_ORIG:" in *":$BIN:"*) ;; *) log "add to your shell profile: export PATH=\"$BIN:\$PATH\"";; esac

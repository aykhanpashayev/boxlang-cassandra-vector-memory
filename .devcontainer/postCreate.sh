#!/usr/bin/env bash
set -euo pipefail

echo "== [postCreate] START =="

# ------------------------------------------------------------
# 1) Fix Codespaces apt-get update failures due to Yarn APT repo
#    (NO_PUBKEY 62D54FD4003F6525 / dl.yarnpkg.com)
# ------------------------------------------------------------
echo "== [postCreate] Fix Yarn APT repo issues (disable/remove) =="

# Remove common Yarn source list files if present
sudo rm -f /etc/apt/sources.list.d/yarn.list || true
sudo rm -f /etc/apt/sources.list.d/yarn*.list || true

# Remove any apt source line containing dl.yarnpkg.com if it exists elsewhere
if sudo grep -R "dl\.yarnpkg\.com" -n /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  echo "Found Yarn repo entries; stripping them..."
  sudo sed -i.bak '/dl\.yarnpkg\.com/d' /etc/apt/sources.list || true
  for f in /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    sudo sed -i.bak '/dl\.yarnpkg\.com/d' "$f" || true
  done
fi

# Clean up any stale lists to avoid cached signature errors
sudo rm -rf /var/lib/apt/lists/*

echo "== [postCreate] apt-get update & base tools =="
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  tar \
  gzip \
  bash \
  coreutils \
  python3 \
  procps \
  netcat-openbsd

# ------------------------------------------------------------
# 2) Install cqlsh reliably via Cassandra binary tarball (no pip)
# ------------------------------------------------------------
CASSANDRA_TOOLS_VERSION="5.0.6"
CASSANDRA_TOOLS_TARBALL="apache-cassandra-${CASSANDRA_TOOLS_VERSION}-bin.tar.gz"
CASSANDRA_TOOLS_URL="https://archive.apache.org/dist/cassandra/${CASSANDRA_TOOLS_VERSION}/${CASSANDRA_TOOLS_TARBALL}"
CASSANDRA_TOOLS_DIR="/opt/apache-cassandra-${CASSANDRA_TOOLS_VERSION}"

echo "== [postCreate] Install cqlsh from Cassandra tools tarball: ${CASSANDRA_TOOLS_URL} =="

if [ ! -d "${CASSANDRA_TOOLS_DIR}" ]; then
  sudo mkdir -p /opt
  curl -fsSL "${CASSANDRA_TOOLS_URL}" -o "/tmp/${CASSANDRA_TOOLS_TARBALL}"
  sudo tar -xzf "/tmp/${CASSANDRA_TOOLS_TARBALL}" -C /opt
  rm -f "/tmp/${CASSANDRA_TOOLS_TARBALL}"
fi

# Symlink cqlsh into PATH
sudo ln -sf "${CASSANDRA_TOOLS_DIR}/bin/cqlsh" /usr/local/bin/cqlsh
sudo chmod +x /usr/local/bin/cqlsh

# Ensure cqlsh can find its python libs if needed
# (Many distros work without this, but this makes it deterministic.)
PROFILE_SNIPPET="/etc/profile.d/cassandra-tools.sh"
if [ ! -f "${PROFILE_SNIPPET}" ]; then
  echo "== [postCreate] Write ${PROFILE_SNIPPET} for PYTHONPATH/PATH stability =="
  cat <<EOF | sudo tee "${PROFILE_SNIPPET}" >/dev/null
export CASSANDRA_HOME="${CASSANDRA_TOOLS_DIR}"
export PATH="\$PATH:${CASSANDRA_TOOLS_DIR}/bin"
# cqlsh uses python + cassandra pylib shipped in the tarball
export PYTHONPATH="\${PYTHONPATH:-}:${CASSANDRA_TOOLS_DIR}/pylib"
EOF
fi

# ------------------------------------------------------------
# 3) Install BoxLang runtime (official quick installer)
# ------------------------------------------------------------
echo "== [postCreate] Install BoxLang runtime (official installer) =="
# System-wide install so `boxlang` is on PATH for everyone.
# If already installed, installer should no-op or upgrade safely.
sudo /bin/bash -c "$(curl -fsSL https://install.boxlang.io)"

# ------------------------------------------------------------
# 4) Health check: wait for Cassandra to accept CQL connections
# ------------------------------------------------------------
echo "== [postCreate] Wait for Cassandra (cassandra:9042) =="
bash .devcontainer/wait-for-cassandra.sh

# ------------------------------------------------------------
# 5) Verify toolchain versions
# ------------------------------------------------------------
echo "== [postCreate] Verify cqlsh =="
cqlsh --version

echo "== [postCreate] Verify boxlang =="
boxlang --version

echo "== [postCreate] DONE =="

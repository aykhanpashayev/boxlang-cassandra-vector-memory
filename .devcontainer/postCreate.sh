#!/usr/bin/env bash
set -euo pipefail

echo "== [postCreate] START =="

# ------------------------------------------------------------
# 1) Fix Codespaces apt-get update failures due to Yarn APT repo
# ------------------------------------------------------------
echo "== [postCreate] Fix Yarn APT repo issues (disable/remove) =="

sudo rm -f /etc/apt/sources.list.d/yarn.list || true
sudo rm -f /etc/apt/sources.list.d/yarn*.list || true

if sudo grep -R "dl\.yarnpkg\.com" -n /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  echo "Found Yarn repo entries; stripping them..."
  sudo sed -i.bak '/dl\.yarnpkg\.com/d' /etc/apt/sources.list || true
  for f in /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    sudo sed -i.bak '/dl\.yarnpkg\.com/d' "$f" || true
  done
fi

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
  netcat-openbsd \
  unzip \
  findutils

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

sudo ln -sf "${CASSANDRA_TOOLS_DIR}/bin/cqlsh" /usr/local/bin/cqlsh
sudo chmod +x /usr/local/bin/cqlsh

PROFILE_SNIPPET="/etc/profile.d/cassandra-tools.sh"
if [ ! -f "${PROFILE_SNIPPET}" ]; then
  cat <<EOF | sudo tee "${PROFILE_SNIPPET}" >/dev/null
export CASSANDRA_HOME="${CASSANDRA_TOOLS_DIR}"
export PATH="\$PATH:${CASSANDRA_TOOLS_DIR}/bin"
export PYTHONPATH="\${PYTHONPATH:-}:${CASSANDRA_TOOLS_DIR}/pylib"
EOF
fi

# ------------------------------------------------------------
# 3) Ensure Java 21+ (BoxLang requirement)
# ------------------------------------------------------------
echo "== [postCreate] Verify Java version (BoxLang requires 21+) =="
JAVA_MAJOR="$(java -version 2>&1 | awk -F[\".] '/version/ {print $2}')"
if [ "${JAVA_MAJOR}" -lt 21 ]; then
  echo "ERROR: Java 21+ required but found Java ${JAVA_MAJOR}. (Use java:1-21-bullseye image)"
  exit 1
fi

# ------------------------------------------------------------
# 4) Install BoxLang runtime from official ZIP (NON-INTERACTIVE)
#    Source: https://downloads.ortussolutions.com/ortussolutions/boxlang/boxlang-latest.zip
# ------------------------------------------------------------
echo "== [postCreate] Install BoxLang runtime from ZIP (no prompts) =="

BOXLANG_ZIP_URL="https://downloads.ortussolutions.com/ortussolutions/boxlang/boxlang-latest.zip"
BOXLANG_DIR="/usr/local/boxlang"
TMP_ZIP="/tmp/boxlang-latest.zip"

# If boxlang already exists, skip download
if command -v boxlang >/dev/null 2>&1; then
  echo "BoxLang already installed: $(command -v boxlang)"
else
  sudo rm -rf "${BOXLANG_DIR}"
  sudo mkdir -p "${BOXLANG_DIR}"

  curl -fsSL "${BOXLANG_ZIP_URL}" -o "${TMP_ZIP}"
  sudo unzip -q "${TMP_ZIP}" -d "${BOXLANG_DIR}"
  rm -f "${TMP_ZIP}"

  # Find the actual boxlang launcher inside the extracted tree
  # Common layout is: /usr/local/boxlang/**/bin/boxlang
  BOXLANG_BIN_PATH="$(sudo find "${BOXLANG_DIR}" -type f -name boxlang 2>/dev/null | head -n 1 || true)"
  if [ -z "${BOXLANG_BIN_PATH}" ]; then
    echo "ERROR: Could not locate 'boxlang' executable inside ${BOXLANG_DIR}"
    sudo find "${BOXLANG_DIR}" -maxdepth 4 -type f | head -n 200 || true
    exit 1
  fi

  sudo chmod +x "${BOXLANG_BIN_PATH}"
  sudo ln -sf "${BOXLANG_BIN_PATH}" /usr/local/bin/boxlang

  # Also ensure libs/scripts can be found when running
  # (some distros rely on relative paths; keep working dir stable)
  cat <<EOF | sudo tee /etc/profile.d/boxlang.sh >/dev/null
export BOXLANG_HOME="${BOXLANG_DIR}"
EOF
fi

# ------------------------------------------------------------
# 5) Health check: wait for Cassandra to accept CQL connections
# ------------------------------------------------------------
echo "== [postCreate] Wait for Cassandra (cassandra:9042) =="
bash .devcontainer/wait-for-cassandra.sh

# ------------------------------------------------------------
# 6) Verify toolchain versions
# ------------------------------------------------------------
echo "== [postCreate] Verify cqlsh =="
cqlsh --version

echo "== [postCreate] Verify boxlang =="
boxlang --version

echo "== [postCreate] DONE =="

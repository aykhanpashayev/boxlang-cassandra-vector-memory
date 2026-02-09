#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "== postCreate: starting =="
echo "whoami: $(whoami)"
echo "pwd: $(pwd)"

echo "== Fix: remove broken Yarn APT source (common Codespaces issue) =="
sudo rm -f /etc/apt/sources.list.d/yarn.list /etc/apt/sources.list.d/yarn*.list || true

echo "== apt-get update =="
sudo apt-get update

echo "== install base tools (curl, python3, docker CLI) =="
sudo apt-get install -y \
  ca-certificates curl tar python3 \
  docker.io docker-compose

echo "== verify docker CLI (optional but useful) =="
docker --version || true
docker compose version || true
docker ps >/dev/null 2>&1 || echo "NOTE: docker daemon not accessible (socket mount issue)."

# -----------------------------
# Install cqlsh reliably (from official Apache Cassandra tarball)
# (we only need the tools; Cassandra itself runs as a separate container)
# -----------------------------
echo "== install cqlsh (Cassandra tools tarball) =="

CASSANDRA_VERSION="5.0.6"
CASSANDRA_DIR="/opt/cassandra"
TGZ="apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz"
URL="https://downloads.apache.org/cassandra/${CASSANDRA_VERSION}/${TGZ}"

sudo mkdir -p "${CASSANDRA_DIR}"
cd /tmp

# download only if missing
if [ ! -f "/tmp/${TGZ}" ]; then
  curl -fL -o "/tmp/${TGZ}" "${URL}"
fi

sudo tar -xzf "/tmp/${TGZ}" -C "${CASSANDRA_DIR}"
sudo ln -sf "${CASSANDRA_DIR}/apache-cassandra-${CASSANDRA_VERSION}/bin/cqlsh" /usr/local/bin/cqlsh

echo "cqlsh:"
cqlsh --version || true

# -----------------------------
# Install BoxLang CLI (official current installer)
# -----------------------------
echo "== install BoxLang CLI (official installer) =="

# This is the current official install command published on the BoxLang download page.
# It should install a system-wide `boxlang` command.
sudo /bin/bash -c "$(curl -fsSL https://install.boxlang.io)"

# Guarantee `boxlang` is discoverable (handle different install locations safely)
if command -v boxlang >/dev/null 2>&1; then
  echo "BoxLang found on PATH: $(command -v boxlang)"
else
  echo "BoxLang not on PATH, searching common locations..."
  for candidate in \
    "/usr/local/bin/boxlang" \
    "/usr/bin/boxlang" \
    "$HOME/.boxlang/bin/boxlang" \
    "/opt/boxlang/bin/boxlang"
  do
    if [ -x "$candidate" ]; then
      echo "Found BoxLang at: $candidate"
      sudo ln -sf "$candidate" /usr/local/bin/boxlang
      break
    fi
  done
fi

echo "== verify BoxLang =="
which boxlang || true
boxlang --version || true

echo "== quick check: wait for Cassandra port 9042 to be ready =="
python3 - << 'PY'
import socket, time
host="cassandra"; port=9042
for i in range(60):
    s=socket.socket(); s.settimeout(1)
    try:
        s.connect((host,port))
        print("OK: cassandra:9042 reachable")
        raise SystemExit(0)
    except Exception:
        time.sleep(2)
    finally:
        try: s.close()
        except: pass
print("WARN: cassandra:9042 not reachable yet (may still be booting).")
PY

echo "== postCreate: done =="
echo "Log saved to: .devcontainer-postCreate.log"

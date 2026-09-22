#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-shot Artemis SSH setup for a NEW machine. Shared by every lab project.
#
#   bash hpc/scripts/setup-ssh.sh <cluster_username>
#
# Generates a machine-local keypair (never copy private keys between
# machines), adds the 'artemis' (and 'artemis-rsa' fallback) host alias to
# ~/.ssh/config, and prints the block to paste into the cluster shell.
# Idempotent: safe to re-run. The username can also come from ARTEMIS_USER,
# or from a project's IGC_HPC_USER / FA_HPC_USER.
# ---------------------------------------------------------------------------
set -euo pipefail

HPC_USER="${1:-${ARTEMIS_USER:-${IGC_HPC_USER:-${FA_HPC_USER:-}}}}"
if [ -z "$HPC_USER" ]; then
  echo "usage: bash hpc/scripts/setup-ssh.sh <cluster_username>   (e.g. dmm56)" >&2
  exit 1
fi
HPC_HOST=ood.artemis.hrc.sussex.ac.uk
KEY="$HOME/.ssh/artemis"

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

if [ -f "$KEY" ]; then
  echo "==> key already exists: $KEY"
else
  echo "==> generating ed25519 keypair for $(hostname)"
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "${HPC_USER}@$(hostname)"
fi
if [ ! -f "${KEY}_rsa" ]; then
  ssh-keygen -t rsa -b 4096 -f "${KEY}_rsa" -N "" -C "${HPC_USER}@$(hostname)-rsa"
fi
chmod 600 "$KEY" "${KEY}_rsa" 2>/dev/null || true

CFG="$HOME/.ssh/config"
if [ -f "$CFG" ] && grep -q "^Host artemis$" "$CFG"; then
  echo "==> ~/.ssh/config already has the 'artemis' alias:"
  awk '/^Host artemis$/{p=1; print; next} /^Host /{p=0} p' "$CFG" | sed 's/^/      /'
  if ! awk '/^Host artemis$/{p=1; next} /^Host /{p=0} p' "$CFG" | grep -q "User ${HPC_USER}\$"; then
    echo "    WARNING: that alias is not for user '${HPC_USER}'. Edit ~/.ssh/config by hand if needed." >&2
  fi
else
  echo "==> adding 'artemis' alias to ~/.ssh/config"
  cat >> "$CFG" <<EOF

# --- Artemis HPC (University of Sussex) ---------------------------------
# Requires the GlobalProtect VPN (portal bond.sussex.ac.uk) to be connected.
Host artemis
    HostName ${HPC_HOST}
    User ${HPC_USER}
    IdentityFile ~/.ssh/artemis
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ConnectTimeout 15
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host artemis-rsa
    HostName ${HPC_HOST}
    User ${HPC_USER}
    IdentityFile ~/.ssh/artemis_rsa
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ConnectTimeout 15
EOF
  chmod 600 "$CFG"
fi

cat <<EOF

---------------------------------------------------------------------------
Next: install this machine's public key on Artemis.

With the VPN connected, open
  https://ood.artemis.hrc.sussex.ac.uk/
then Clusters -> ">_ artemis Shell Access" and paste this whole block:

mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys <<'KEYS'
$(cat "${KEY}.pub")
KEYS
chmod 600 ~/.ssh/authorized_keys && echo OK

Then check it from here with:
  ssh artemis 'whoami; hostname'

(Only if ed25519 is refused, append ${KEY}_rsa.pub the same way and use
the 'artemis-rsa' alias.) Record the key in hpc/private/accounts.md.
---------------------------------------------------------------------------
EOF

# My Artemis account — PRIVATE

<!-- Copy to hpc/private/accounts.md (gitignored) and fill in. Never commit
     passwords or private keys; public keys and paths are fine here. -->

## Account

| | |
| --- | --- |
| cluster username | `<user>` |
| school directory (`<group>`) | `psych` |
| Unix groups (`id -Gn`) | e.g. `artemis_sussexneuro` |
| VPN | GlobalProtect, portal `bond.sussex.ac.uk`, username `<user>`, Sussex password + authenticator code |
| OOD | <https://ood.artemis.hrc.sussex.ac.uk/>, username `<user>`, Sussex password |

## Paths

- home: `/mnt/nfs2/<group>/<user>/` (check with `echo ~`)
- long-term: `/mnt/lustre/users/<group>/<user>/`
- scratch: `/mnt/lustre/scratch/<group>/<user>/`
- R library: `/mnt/lustre/users/<group>/<user>/cluster_R_libs/x86_64-pc-linux-gnu-library/4.3`
- CmdStan: `~/.cmdstan/cmdstan-<ver>`

## Projects on this account

| project repo | cluster dir (users + scratch) | status | notes |
| --- | --- | --- | --- |
| | | active / frozen / archived | |

## Machines and SSH keys installed

| machine | key (`~/.ssh/artemis.pub`) | added |
| --- | --- | --- |
| | `ssh-ed25519 AAAA...` | |

## Account quirks

<!-- e.g. what ~/.bashrc and ~/.Renviron set; see toolchain.md#the-brms-trap -->

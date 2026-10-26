# Setup — new machine, new account, new project

Three independent levels. Do only the ones that are new.

| level | how often | steps |
| --- | --- | --- |
| [A. a new machine](#a-new-machine) | once per laptop/desktop | VPN client, SSH key, alias |
| [B. a new cluster account](#b-new-cluster-account) | once per person | clean `.bashrc`, R library, CmdStan, precompiled header |
| [C. a new project on an account](#c-new-project-on-an-account) | once per project × account | project dirs, `hpc.local`, first push |

Record what you set up in your gitignored `hpc/private/accounts.md`
(template: [accounts.template.md](accounts.template.md)).

---

## Before anything: get an account

Artemis accounts are requested from Sussex IT / research computing (see
[Access](https://artemis-docs.hpc.sussex.ac.uk/artemis/access.html)). For the
departmental `sussexneuro` partition, also ask to be added to the
`artemis_sussexneuro` Unix group ([artemis.md#sussexneuro](artemis.md#sussexneuro)).

## A. New machine

1. **Install GlobalProtect** and connect to portal `bond.sussex.ac.uk`
   (Sussex password followed by the authenticator code).
2. **Create the SSH key and alias** — from a bash shell (Git Bash on Windows):

   ```bash
   bash hpc/scripts/setup-ssh.sh <your_cluster_username>
   ```

   It generates `~/.ssh/artemis` (ed25519, no passphrase, so agents can use
   it headlessly) plus an RSA fallback, adds the `artemis` host alias to
   `~/.ssh/config`, and prints a block to paste into the cluster. Idempotent.
   One key per machine; **never copy a private key between machines**.
3. **Install the public key**: OOD → Clusters → `>_ artemis Shell Access`,
   paste the printed block. It appends to `~/.ssh/authorized_keys`.
4. **Check**: `ssh artemis 'whoami; hostname'` should print your username and
   `artemis-login-0` without a password prompt.

A machine set up once serves every project: the alias is shared.

On Windows, project drivers prefer `C:\Windows\System32\OpenSSH\ssh.exe` when
present; it reads the same `~/.ssh` as Git Bash, so nothing else is needed.

## B. New cluster account

Do this on the login node (`ssh artemis`). Most of it is a one-time
toolchain build; [toolchain.md](toolchain.md) explains every choice.

### B1. Look at the login environment

```bash
cat ~/.bashrc ~/.Renviron 2>/dev/null
```

- Old accounts' `~/.bashrc` may still `module load sge` and
  `module load easybuild/software`. Neither module exists; delete the lines
  (harmless otherwise, but every login prints two Lmod errors).
- **Look for `R_LIBS_USER`** in `~/.bashrc` or `~/.Renviron`. On `dmm56`,
  `~/.bashrc` points it at a third-party shared library
  (`/research/cisc2/shared/...`) that silently supplies brms. That is the
  single biggest reason one account works and another does not — read
  [toolchain.md#the-brms-trap](toolchain.md#the-brms-trap) before copying it.
  A project whose `.slurm` files set `R_LIBS_USER` themselves does not need
  the line.
- **Jobs are not insulated from either file** (corrected 2026-10-26). A batch
  script does not read `~/.bashrc`, but `sbatch` copies the environment of
  the shell that submitted it, and a driver submitting over ssh has read
  `~/.bashrc`. Setting `R_LIBS` does not shut out `R_LIBS_USER`: R searches
  both. `~/.Renviron` is read by R itself in every job: `dmm56`'s
  `R_MAX_VSIZE=100Gb` capped a combine job's memory in IllusionGameComputational
  on 2026-10-23.

### B2. Build the R library and CmdStan

From any project with a driver (on your own machine, VPN up):

```bash
cd analysis/server
./hpc check          # VPN + SSH
./hpc setup          # project dirs
./hpc install        # project R library + CmdStan if missing (~25 min the first time)
./hpc precompile     # the CmdStan precompiled header, once
```

`install` and `precompile` run on a compute node through `srun`, never on the
login node. Both are per **account**, not per project: the second project on
an account finds them already built and finishes in seconds.

Verify:

```bash
ssh artemis 'ls ~/.cmdstan; ls ~/.cmdstan/*/stan/src/stan/model/model_header.hpp.gch/'
```

The variant our jobs need is `model_header_threads_nochecks_12_3.hpp.gch`
([toolchain.md#precompiled-header](toolchain.md#precompiled-header)).

### B3. Smoke-test before any real run

Run the project's smoke test (tiny data, `short` partition, own output dir —
[jobs.md#test-runs](jobs.md#test-runs)). A fresh account that fails *every*
model at compile time within a minute is the brms trap, not your model. If
the project logs the brms it loaded, anything other than
`brms 2.21.0 from /research/cisc2/...` shows it before the compile does.

## C. New project on an account

1. Make sure the project has a `server/` folder following
   [project-template.md](project-template.md).
2. If you are **not** the account the scripts default to, create the
   gitignored per-machine override (the prefix is the project's):

   ```bash
   echo 'FA_HPC_USER=<you>' > analysis/server/hpc.local      # FakeArt
   echo 'IGC_HPC_USER=<you>' > analysis/server/hpc.local     # IllusionGameComputational
   ```

   Add `<PREFIX>_HPC_GROUP=<school>` if you are not in `psych`. This changes
   the *paths*; who you log in as comes from your `~/.ssh/config`.
3. `./hpc check && ./hpc setup && ./hpc push`, then the smoke test.
4. Agree with collaborators **who fits what** before submitting production
   runs; the split exists to use two sets of quotas
   ([jobs.md#splitting-work-across-accounts](jobs.md#splitting-work-across-accounts)).

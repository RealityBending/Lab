# Toolchain — R, brms, cmdstanr and CmdStan on Artemis

The stack our Bayesian projects use. Every row below has broken a run at
least once when changed; change one piece at a time and smoke-test.

- [The working stack](#the-working-stack)
- [Modules](#modules)
- [The project R library](#the-project-r-library)
- [CmdStan](#cmdstan)
- [Precompiled header](#precompiled-header)
- [The brms trap](#the-brms-trap) — why a second account fails
- [cogmod](#cogmod)

---

## The working stack

Verified on `dmm56`, 2026-09-22.

| piece | value | why |
| --- | --- | --- |
| module | `CmdStanR/0.7.1-foss-2023a-R-4.3.2` | the only module stack shipping **mgcv + brms + cmdstanr together**. `R/4.4.1-gfbf-2023b` loads but has neither `mgcv` nor `cmdstanr` |
| R | 4.3.2 (GCC 12.3, foss-2023a) | comes with the module |
| brms | 2.21.0, from a borrowed library on `R_LIBS_USER` (re-verified 2026-10-26) | **not from the module** (which ships 2.20.4) — see [the brms trap](#the-brms-trap) |
| cmdstanr | ≥ 0.8 (0.9.0 installed), from the project library | the module's 0.7.1 **cannot read CmdStan ≥ 2.36 output** (fails with `invalid 'y' type in 'x && y'`) |
| CmdStan | 2.39.0 in `~/.cmdstan` | built for GCC 12.3 |
| processx | 3.8.2, from the module (seen 2026-10-13) | below 3.9 it tags cmdstanr's chain processes from R's RNG, so tasks that `set.seed()` alike can kill each other's chains: [troubleshooting](troubleshooting.md#chains-killed-by-a-sibling-task) |
| project R library | `/mnt/lustre/users/<group>/<user>/cluster_R_libs/x86_64-pc-linux-gnu-library/4.3` | holds what the module lacks; precedes it on `R_LIBS` |
| cogmod | ≥ 0.3.3 (`dev` branch) | see [cogmod](#cogmod) |

## Modules

Two Artemis quirks that every `.slurm` file must work around
([jobs.md#the-slurm-script](jobs.md#the-slurm-script) has the preamble):

1. **`module` is undefined in batch scripts.** SLURM runs them
   non-interactively; source `/etc/profile.d/lmod.sh` first.
2. **Compute nodes cannot see the EasyBuild modules.** Login nodes have
   `/mnt/shared/easybuild/modules/all` on `MODULEPATH`; compute nodes only
   `/opt/ohpc/pub/modulefiles`. Run
   `module use /mnt/shared/easybuild/modules/all` before `module load`, or the
   job dies with *"module(s) exist but cannot be loaded as requested"* then
   `Rscript: command not found`.

Browse what exists (login node): `module use /mnt/shared/easybuild/modules/all; module avail R/ CmdStanR`.

## The project R library

One library **per account, shared by all that account's projects** (same
path, same R minor version). Consequences:

- Refreshing a package from one project refreshes it for all of them. Do not
  install an *older* version of a shared package (e.g. cogmod `main` when
  another project needs `dev`) without checking the other projects' floors.
- Each project's `install_pkgs.R` adds only what *it* needs; the union
  accumulates. Name every package a job needs, including `Suggests` a package
  only uses optionally (e.g. `emmeans`, `marginaleffects` for `modelbased`).
- Installs run through `srun` on a compute node (`./hpc install`). Naming a
  package forces a reinstall (`./hpc install cogmod`); `./hpc install all`
  reinstalls everything.
- **Version floors fail the install, not the job.** A package present but too
  old is not "missing", so check versions explicitly and `stop()` in the
  installer. Example: `marginaleffects` needs `collapse ≥ 2.0.18`; the module
  ships an older one that shadows nothing until the project library gets a
  newer copy.
- When checking a version, use
  `packageVersion(p, lib.loc = .libPaths())`: with the default it reports the
  *loaded* namespace, which can be the module's stale copy even after a newer
  one was installed in the same session.

## CmdStan

Lives in `~/.cmdstan/cmdstan-<version>` (home: small, backed up), found
automatically by cmdstanr. A fresh account has none; the installers build it
with `cmdstanr::install_cmdstan()` (~15–25 min, once per account). Pin the
version you build across accounts — a fresh `install_cmdstan()` grabs the
latest, which is how a colleague ended up on 2.37 while `dmm56` ran 2.39.

A corrupt install (e.g. after the header race below) is repaired with:

```bash
Rscript -e 'cmdstanr::rebuild_cmdstan(cores = 8)'   # inside srun, module loaded
```

## Precompiled header

CmdStan precompiles a header into
`~/.cmdstan/<version>/stan/src/stan/model/model_header.hpp.gch/` — a
**directory** holding one ~800 MB variant per compiler + flag combination:

```
model_header_12_3.hpp.gch                    # GCC 12.3, plain
model_header_nochecks_12_3.hpp.gch           # no range checks
model_header_threads_nochecks_12_3.hpp.gch   # threaded, no range checks  <- what our brms fits use
```

**If the variant a job needs is absent when an array starts, every task
races to build it** and all but one die in minutes with:

```
error: while reading precompiled header: No such file or directory
```

The losers leave a **corrupt** variant, after which nothing compiles until
`rebuild_cmdstan()`. On 2026-09-17 this killed 10 of 12 tasks.

Prevention: compile one trivial model with the **exact** `cpp_options` the
fits use, once, before the first array (`./hpc precompile`; the reference is
FakeArt's `analysis/server/precompile.R`). Having *a* `.gch` is not having
*ours* — check for the variant by name. Re-run after any change to the
module, the CmdStan version, or the fits' `cpp_options`.

Two non-fixes, both tried: `PRECOMPILED_HEADERS=false` in `make/local`
(cmdstanr rewrites that file on every compile), and `rm -f .../model/*.gch`
(the glob matches the directory; `rm -f` refuses it).

## The brms trap

Status: **open**, with a per-project workaround since 2026-10-26. Read this
before setting up a second account or debugging a compile error that hits
*every* model.

On a fresh account, every model fails to compile within a minute. It
happened on 2026-09-21 (~40 s) and again on another new account on
2026-10-26 (17 s):

```
Syntax error in model_<hash>.stan, line 10:
   int[] sequence(int start, int end) {
Ill-formed type. Expected an unsized type in function signature.
```

1. The module's brms 2.20.4 generates old Stan array syntax (`int[] ...`),
   removed in CmdStan 2.33. A fresh `install_cmdstan()` is far newer (2.37 on
   2026-09-21).
2. On 2026-09-21, upgrading brms in the project library (2.21.0, 2.23.0)
   cleared that and hit a second error: a C++ template mismatch in the
   `reduce_sum` threading code brms generates.

Why `dmm56` works (re-verified 2026-10-26): its **`~/.bashrc`** has

```bash
export R_LIBS_USER=/research/cisc2/shared/cluster_R_libs/x86_64-pc-linux-gnu-library/4.2/
```

This section said `~/.Renviron` until 2026-10-26. That file only sets
`R_MAX_VSIZE`. The path is a library **belonging to another research group**
(`cr291`). Anyone can read it (`other::r-x` on every directory, the files
644), and it holds brms 2.21.0, built under R 4.2.1 on 2024-05-14 and
unchanged since.

It reaches the jobs by inheritance, not through the batch script. The
project's `./hpc` driver runs `sbatch` over a non-interactive ssh command,
bash reads `~/.bashrc` for those, and `sbatch`'s default `--export=ALL`
copies the submitting shell's environment into the job.

Inside the job, R searches `R_LIBS` (the project library) first, then
`R_LIBS_USER`, then `R_LIBS_SITE`. The last is where the `CmdStanR` modulefile
and its `R-bundle-CRAN/2023.12` dependency put their packages. Setting
`R_LIBS` therefore does not shut `R_LIBS_USER` out: both are on the path. A
test on 2026-10-26 (`srun`, `R_LIBS_USER` removed first) loaded
`brms 2.20.4 from .../R-bundle-CRAN/2023.12-foss-2023a/brms` without it, and
`brms 2.21.0 from /research/cisc2/...` with it.

So the "working" brms is borrowed infrastructure we do not control, and no
installer reproduces it.

What to do:

- **Set `R_LIBS_USER` in the project, not the account.** This is the
  workaround, in IllusionGameComputational since 2026-10-26. The driver passes
  `XX_R_LIBS_USER` (default: the path above) to every job with `--export`,
  and sets `R_LIBS_USER` for `install` and `precompile`. Every `.slurm`
  exports it, with the same default for hand submissions, and logs the brms
  it got ([jobs.md#the-slurm-script](jobs.md#the-slurm-script)):

  ```bash
  export R_LIBS_USER="${XX_R_LIBS_USER:-/research/cisc2/shared/cluster_R_libs/x86_64-pc-linux-gnu-library/4.2/}"
  Rscript -e 'cat("brms", format(packageVersion("brms")), "from", find.package("brms"), "\n")'
  ```

  Any account then gets `dmm56`'s brms, with nothing in its `~/.bashrc`. A
  brms installed in the project library would still win, since `R_LIBS`
  comes first. A log line other than `brms 2.21.0 from /research/cisc2/...`
  is this trap.
- **Account stopgap:** put the same `export` line in the new account's
  `~/.bashrc`. It works for anything submitted from a login shell, and it
  inherits the same dependency.
- **Record what a working account actually loads**, inside a job or `srun`
  with the module loaded:
  `Rscript -e 'Sys.getenv("R_LIBS_USER"); find.package("brms"); packageVersion("brms")'`.
- **The real fix** is still not applied: pin brms 2.21.0 and the matching
  CmdStan (2.39.0 on `dmm56`) in the installers, so that a fresh account
  reproduces the working stack without the borrowed library. Item 2 above
  shows it needs a smoke test of its own. Whoever applies it: update this
  section and [setup.md](setup.md).

## cogmod

Our own package, installed from GitHub
(`DominiqueMakowski/cogmod@<ref>`), so it only moves on an explicit
`./hpc install cogmod`. The projects' fits refuse to start below **0.3.3**,
which is on the `dev` branch until merged; the ref defaults to `dev` in both
projects so neither downgrades the shared library under the other. When
0.3.3 lands on `main`, switch the default in every project's driver at once.

Note the date the library was refreshed when comparing fits: priors and inits
come from the cogmod version **at submission time**, not from anything in the
project repo. Print `packageDescription("cogmod")$RemoteSha` in job logs.

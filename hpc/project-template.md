# Project template — how a project uses the cluster

What a project repo should contain to run on Artemis, and what it should
*not* (because it lives in this hub). Two projects follow this layout:
[IllusionGameComputational](https://github.com/RealityBending/IllusionGameComputational)
and [FakeArt](https://github.com/RealityBending/FakeArt). **FakeArt's
`analysis/server/` is the more recent reference implementation** — copy from
it when starting a new project.

## What lives where

| in the project (`analysis/server/`) | in this hub |
| --- | --- |
| the `./hpc` driver (project prefix, project commands) | access, storage, partitions, quotas |
| the model/job registry (`models.R`) | the R/Stan toolchain and its traps |
| `fit_model.R`, `combine_model.R`, `*.slurm` | how to write `.slurm` files, size, submit, monitor |
| `install_pkgs.R` (the packages *this* project needs) | troubleshooting of cluster-level errors |
| measurements of *this* project's jobs (runtimes, memory, convergence) | housekeeping policy and the audit script |
| `AGENT.md`: project decisions, open questions | per-machine SSH setup (`scripts/setup-ssh.sh`) |
| `hpc.local` (gitignored): this machine's account | `private/` (gitignored): accounts, keys, audit log |

If you find yourself writing a fact that would be true for any project,
write it here instead and link to it.

## The pointer block

At the top of the project's agent instructions:

```markdown
> **Cluster-level instructions live in the lab HPC hub**:
> <https://github.com/RealityBending/Lab/tree/main/hpc> (start at `hpc/README.md`).
> Prefer a local clone of `RealityBending/Lab` if there is one — it also holds
> your gitignored `hpc/private/` notes. The hub wins over anything here that
> contradicts it; this file only holds what is specific to this project.
```

## Layout

```
analysis/server/
  hpc               driver (bash, LF)
  models.R          registry: one entry per model; the only definition of a model
  fit_model.R       fits the one model named by <PREFIX>_MODEL; one shard per array task
  fit.slurm         generic array job; #SBATCH defaults = the production config
  combine_model.R   merges one model's shards
  combine.slurm
  install_pkgs.R    builds / checks the (shared) project R library
  precompile.R      builds the CmdStan precompiled header with the fits' exact cpp_options
  README.md         command reference for this project
  AGENT.md          project-specific measurements, decisions, open questions
  hpc.local         gitignored: <PREFIX>_HPC_USER=<you>
```

Plus, at the repo root:

```gitignore
# .gitignore
analysis/server/hpc.local
```

```gitattributes
# .gitattributes — cluster-side files must be LF
*.slurm              text eol=lf
*.sh                 text eol=lf
analysis/server/hpc  text eol=lf
analysis/server/*.R  text eol=lf
```

## The driver contract

Whatever a project's `./hpc` adds, keep these properties — each one is a
lesson from a failed run:

1. **A unique variable prefix** (`IGC_`, `FA_`, ...) for every setting, so
   projects can be driven from the same shell.
2. **Nothing account-specific is hard-coded.** `<PREFIX>_HPC_USER` and
   `<PREFIX>_HPC_GROUP` derive every path; `hpc.local` is sourced first;
   the environment overrides the file.
3. **`check`** confirms VPN + SSH and prints quota usage.
4. **`push` mirrors** top-level `*.R` / `*.slurm` through **one tar pipe**,
   strips CR, and deletes cluster copies of scripts that no longer exist
   locally. It never touches outputs or logs.
5. **`install` / `precompile` run through `srun`** on a compute node.
6. **Names are validated** against the registry before submission; `all`
   expands to every entry.
7. **All submissions in one call go through one SSH connection**, each line
   labelled and suffixed `|| echo 'SUBMIT FAILED'`.
8. Paths, module, library and run-shaping variables reach the job through
   `sbatch --export`; the `.slurm` falls back to sane defaults when submitted
   by hand.
9. **`queue`** and **`progress`** give cheap status (state; latest iteration
   per chain; the summary line); **`log`** is for when something is wrong.
10. **`pull` stages outside the repo, verifies byte sizes, then moves**
    (Dropbox-safe).
11. `sh '<cmd>'` for anything else, one connection.

## Starting a new project

1. Copy FakeArt's `analysis/server/` (driver, `.slurm`, installer,
   precompile) into the new repo; rename the prefix and `PROJECT` dir name;
   empty the registry.
2. Add the `.gitignore` / `.gitattributes` lines above and the pointer block.
3. Follow [setup.md#c-new-project-on-an-account](setup.md#c-new-project-on-an-account).
4. Add the project to the table in your `hpc/private/accounts.md` so audits
   know whose directory is whose.

The driver is still duplicated per project, so an improvement in one (e.g.
FakeArt's single-connection submit and staged pull, 2026-09-22) must be
ported to the others by hand. If the drivers keep converging, the next step
is to move the generic part into this hub as a shared library that each
project's `hpc` sources.

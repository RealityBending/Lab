# HPC — the lab's shared instructions for Artemis

This folder is the **single source of truth for everything cluster-level** about
running Reality Bending Lab work on **Artemis**, the University of Sussex HPC:
access, storage, partitions and quotas, the R/Stan toolchain, how to write and
monitor jobs, known traps, and keeping our storage tidy.

Project repos keep only what is specific to them (their models, their
measurements, their `./hpc` driver) and **point here** for the rest. If a fact
would be true for any project on the cluster, it belongs here, not in a project.

It is written to be read by agents first and humans second: short files, one
topic each, headings that can be jumped to, commands that can be pasted.

## Where to start

| you want to... | read |
| --- | --- |
| set up a new machine or a new cluster account | [setup.md](setup.md) |
| know what the cluster offers (storage, partitions, quotas, priority) | [artemis.md](artemis.md) |
| install or debug R / brms / cmdstanr / CmdStan on the cluster | [toolchain.md](toolchain.md) |
| write, size, submit, monitor, or collect a job | [jobs.md](jobs.md) |
| fix something that broke | [troubleshooting.md](troubleshooting.md) — symptom → cause → fix |
| tidy up / audit what we store on the cluster | [housekeeping.md](housekeeping.md) |
| start a new project that uses the cluster | [project-template.md](project-template.md) |

Scripts:

| script | what it does |
| --- | --- |
| [scripts/setup-ssh.sh](scripts/setup-ssh.sh) | once per machine: SSH key + `artemis` alias in `~/.ssh/config` |
| [scripts/audit.sh](scripts/audit.sh) | read-only storage audit of an account, over one SSH connection |

## Rules for agents working on the cluster

These apply in every project. Each links to its reason.

1. **VPN first.** Nothing works without the GlobalProtect VPN (portal
   `bond.sussex.ac.uk`). If SSH fails, say so and ask the user to connect;
   do not retry in a loop. ([artemis.md#access](artemis.md#access))
2. **Few SSH connections.** sshd rate-limits bursts. Batch remote work into
   *one* `ssh` call (a server-side loop, a heredoc, a tar pipe), never a
   local `for` loop of `ssh` calls. ([troubleshooting.md](troubleshooting.md#ssh-connection-reset))
3. **Never compile or compute on the login node.** Use `srun` / `sbatch`.
4. **Nothing on Lustre is backed up.** Never delete or overwrite anything on
   the cluster without the user's explicit go-ahead for that specific list.
   Audits are read-only and *propose*; the user decides.
   ([housekeeping.md](housekeeping.md))
5. **Check capacity before blaming a partition.** The account-wide cap is
   550 CPUs across *all* partitions. ([artemis.md#quotas](artemis.md#quotas))
6. **`sussexneuro` is a shared group pool.** Look at who is using it before
   submitting there, and prefer our own quotas when they are free.
   ([artemis.md#sussexneuro](artemis.md#sussexneuro))
7. **Status requests are cheap.** Report `squeue` state plus the latest
   progress line per chain and an ETA — not a log dump.
   ([jobs.md#monitoring](jobs.md#monitoring))
8. **Test runs get their own output directory**, so they can never be adopted
   as production results. ([jobs.md#test-runs](jobs.md#test-runs))
9. **Never touch another person's account** (permissions, files, jobs). Ask
   them.
10. **Keep this hub current.** When you learn or re-verify a cluster-level
    fact, update the relevant file here with the date, and remove the
    duplicate from the project if there is one. Facts carry a *verified on*
    date because the cluster changes under us.

## Public vs private

This repo is **public**. Tracked files contain nothing secret: account IDs
that already appear in our public project repos are fine; passwords, private
keys, and personal notes are not.

Private material goes in **`hpc/private/`**, which is gitignored. Each person
keeps their own (for the lab lead it syncs across machines via Dropbox; a
colleague's clone starts empty). Start from the template:

```bash
mkdir -p hpc/private && cp hpc/accounts.template.md hpc/private/accounts.md
```

`hpc/private/` holds, per person: cluster account and group, machines and the
SSH public keys installed from them, project directories on the cluster, and
the housekeeping audit log.

## How a project points here

Put this block near the top of the project's agent instructions (e.g.
`AGENTS.md` or `analysis/server/AGENT.md`):

```markdown
> **Cluster-level instructions live in the lab HPC hub**:
> <https://github.com/RealityBending/Lab/tree/main/hpc> (start at `hpc/README.md`).
> Prefer a local clone of `RealityBending/Lab` if there is one — it also holds
> your gitignored `hpc/private/` notes. The hub wins over anything here that
> contradicts it; this file only holds what is specific to this project.
```

See [project-template.md](project-template.md) for the recommended layout of
a project's `server/` folder and the contract its `./hpc` driver should keep.

## Provenance

Consolidated on 2026-09-22 from the `analysis/server/` docs of
[IllusionGameComputational](https://github.com/RealityBending/IllusionGameComputational)
and [FakeArt](https://github.com/RealityBending/FakeArt), where these facts
were measured between 2026-09-17 and 2026-09-22, plus the public
[Artemis documentation](https://artemis-docs.hpc.sussex.ac.uk/artemis/).
Project-specific measurements (model runtimes, convergence) stayed in those
repos.

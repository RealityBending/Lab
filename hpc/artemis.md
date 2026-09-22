# Artemis — what the cluster is and what it allows

Reference facts about the Sussex HPC. Each section says when it was last
verified; re-verify anything that matters before relying on it, and update
the date here when you do.

- [Access](#access)
- [Hardware](#hardware)
- [Storage](#storage)
- [Partitions](#partitions)
- [Quotas](#quotas) — per partition, per account, per group
- [sussexneuro](#sussexneuro) — the departmental partition
- [Scheduling and priority](#scheduling-and-priority)
- [Useful commands](#useful-commands)

---

## Access

| | |
| --- | --- |
| VPN (required for everything) | GlobalProtect, portal `bond.sussex.ac.uk`; Sussex username, password followed by the authenticator code |
| SSH / login host | `ood.artemis.hrc.sussex.ac.uk` (lands on `artemis-login-0`) — use the `artemis` alias from [setup.md](setup.md) |
| Open OnDemand (web UI) | <https://ood.artemis.hrc.sussex.ac.uk/> — Sussex username + password |
| shell in the browser | OOD → Clusters → `>_ artemis Shell Access` |
| submit a `.slurm` by hand | OOD → Jobs → Jobs Composer |
| browse files | `https://ood.artemis.hrc.sussex.ac.uk/pun/sys/dashboard/files/fs//mnt/lustre/users/<group>/<user>/` |
| official docs | <https://artemis-docs.hpc.sussex.ac.uk/artemis/> (public) |

Accounts are Sussex usernames (e.g. `dmm56`). Our school directory on Lustre
is `psych`; a colleague in another school has a different `<group>`.

## Hardware

Verified 2026-09-22. 17 nodes shared by every partition: `artemis-a40-*`,
`artemis-rtx-*`, `artemis-cpu-01`, `artemis-general-01/02` — 2,176 CPUs in
total. Nodes are 128 CPUs with ~478–733 GB RAM. Compute nodes **have outbound
internet** (jobs can read data straight from GitHub raw URLs).

Nodes differ a lot in speed and load: the same job measured **2–3× apart in
wall time** depending on placement (idle zen5 `rtx-02` vs a busy zen3 `a40`).
Compare runs by per-iteration or per-gradient cost, never by wall time alone.

`artemis-rtx-00` threw transient Lustre `Input/output error`s on 2026-09-22
(4 of 9 jobs); see [troubleshooting.md](troubleshooting.md#inputoutput-error).

## Storage

Verified against the Artemis docs and our accounts, 2026-09-22.

| area | path | size | backed up? | use it for |
| --- | --- | --- | --- | --- |
| home | `~` = `/its/home/<user>`, a link to `/mnt/nfs2/<group>/<user>` | small (size not documented) | **yes**, nightly | config, `~/.cmdstan`, `~/.ssh` |
| Lustre users | `/mnt/lustre/users/<group>/<user>/` | **2 TB and ~4 million files** per user | **no** — deletion or corruption is unrecoverable | code, R library, fitted models |
| Lustre scratch | `/mnt/lustre/scratch/<group>/<user>/` | no quota | **no** | job logs, temporary files only |
| Lustre projects | `/mnt/lustre/projects/<dep>/<name>` | 20 TB (docs) | no | shared project space; request via support |
| job-local disk | `$TMPDIR` | node disk | no | created at job start, **deleted at job end** |

**The 2 TB is policy, not an enforced limit** (as of 2026-09-22):
`lfs quota -u $USER /mnt/lustre` reports quota and limit `0k` ("default
quota setting"). Nothing will stop us filling it, which is why
[housekeeping.md](housekeeping.md) exists.

**Scratch is purgeable.** The docs say data "may persist here for a maximum of
21 days before it is removed" on one page and reserve "the right to remove any
data over 90 days old" on another. Files older than that have survived in
practice (the 2026-09-22 audit found 510-day-old files), but treat that as luck:
**nothing you need may live only in scratch.** Record measurements from logs
in the project docs soon after a run.

**Lustre is not an archive.** Anything worth keeping long-term (final fitted
models, results) must also live somewhere backed up — see
[housekeeping.md#long-term-homes](housekeeping.md#long-term-homes).

**Permissions.** Every user directory under `/mnt/lustre/users/psych/` is
`drwx------` and owned by the user's personal group (`<user>_g`), so no one
can read another account's files, whatever the permissions further down.
Scratch is the same. Hand files over instead
([jobs.md#sharing-results-between-accounts](jobs.md#sharing-results-between-accounts)).

## Partitions

Verified with `sacctmgr` / `scontrol`, 2026-09-17 → 2026-09-22.

| partition | max wall | max CPUs per user | max RAM per user | notes |
| --- | --- | --- | --- | --- |
| `short` | 2 h | 550 | 3.6 TB | smoke tests, installs |
| `general` (default) | 8 h | 400 | 2.7 TB | the workhorse |
| `long` | 8 days | **140** | 900 GB | the cap bites fast: 8 × 16-CPU tasks |
| `verylong` | 30 days | 70 | 900 GB | rarely worth it: half of `long`'s CPUs |
| `gpu` | 3 days | 300 | 2.1 TB | GPU jobs only, by policy |
| `sussexneuro` | 60 days | *group pool*: 256 CPUs / 1 TB / 4 GPUs | | [see below](#sussexneuro) |

- There is **no 24-hour tier**.
- Every partition has `DefaultTime=NONE`: a job that passes **no `--time`
  gets the partition's maximum**. Choosing the partition *is* the wall-clock
  decision (see [jobs.md#wall-time](jobs.md#wall-time)).
- Defaults if you request nothing: 1 CPU per task, 4 GB per CPU, `general`.

## Quotas

Three layers, and the one that binds is not always the one you expect.
Verified 2026-09-22 with
`sacctmgr -nP show qos format=Name,GrpTRES,MaxTRESPU` and
`sacctmgr -nP show assoc user=<user> format=Account,Partition,QOS`.

| QoS | applies to | limit |
| --- | --- | --- |
| **`normal`** | the account's association — **every job, whatever the partition** | **550 CPUs per user** |
| `short` / `general` / `long` / `verylong` | that partition | 550 / 400 / 140 / 70 CPUs per user |
| `neuro` | `sussexneuro` | 256 CPUs **per group** (`GrpTRES`), no per-user cap |

Consequences:

- **Caps are per user, not per project.** Two projects on one account compete
  for the same 140 CPUs on `long`. A colleague's account has its own full set
  of quotas, which is the cheapest way to double throughput.
- **Partition caps are separate from each other**, so a `long` array at its
  140 ceiling does not stop a `general` or `sussexneuro` job starting — until
  the **sum across partitions reaches 550**. On 2026-09-22 the account held
  `general 400 + long 128 + sussexneuro 64 = 592` and nothing else would start
  anywhere; switching partition was the wrong lever.
- `QOSMaxCpuPerUserLimit` in `squeue` names no QoS, so it reads the same for
  a partition cap and the account cap. Tell them apart by summing your running
  CPUs (command below): under 550 it is the partition; at or over, `normal`.
- Concurrency on a partition is `floor(cap / cpus-per-task)`, shared across
  *all* your jobs there. Size arrays so the widths add up to it.

## sussexneuro

The departmental partition. Verified 2026-09-22 (and the
[Artemis page](https://artemis-docs.hpc.sussex.ac.uk/artemis/department_resources.html)).

- **Access** requires membership of the Unix group `artemis_sussexneuro`
  (managed by the PI who bought the hardware). `dmm56` has it as of
  2026-09-22. Check with `id -Gn`, and by a bare `sbatch -p sussexneuro`.
- **A partition list is not an access check**: `-p sussexneuro,general` is
  accepted and silently runs on `general`, and `--test-only` on the list
  falsely reports `sussexneuro`. Only a bare `-p sussexneuro` fails loudly.
- **It is a second allowance, not a bigger one.** Same 17 nodes; what it adds
  is a quota separate from the partition caps (still inside the account's 550)
  and **higher priority** (`PriorityJobFactor=20000` vs 10000, QoS priority
  2000 vs 1000, and the partition weight is the largest term in the formula).
- **The 256 CPUs are shared with every group member**, including our own other
  projects. Look before sizing:
  `squeue -p sussexneuro -o '%.10i %.10u %.8T %.5C %.12L'`.
- **Over-quota requests are rejected, not queued** (`DenyOnLimit`):
  `sbatch: error: QOSGrpCpuLimit`. Nothing is left pending; resubmit by hand.
- **60 days is not 60 usable days.** Artemis asks that jobs running beyond
  8 days **checkpoint at least daily**, and recommends staying under 14 days,
  so the cluster can take maintenance downtime. Stan cannot checkpoint
  mid-chain, so treat it as *8 days at higher priority*.
- `PreemptMode=GANG,SUSPEND` looks alarming but does not bite: every partition
  is `PriorityTier=1` under `preempt/partition_prio`, so nothing preempts.

Etiquette: use our own `general`/`long` quotas first; reach for `sussexneuro`
when they are full or a job must run alongside another project's, and say in
the project log that you did.

## Scheduling and priority

Slurm priority is dominated by **partition** and **association**, then age and
TRES (resources requested). Practical rules:

- Request only the CPUs and RAM you will use — over-requesting enlarges the
  job's TRES and delays dispatch. Measure memory once and size to it
  ([jobs.md#sizing](jobs.md#sizing)).
- Many small tasks dispatch sooner than one large one.
- **Trimming `--time` does not speed dispatch** here; the CPU caps do the
  queueing. See [jobs.md#wall-time](jobs.md#wall-time).
- FairShare penalises sustained heavy use; idle interactive sessions hurt most.

## Useful commands

Run on the login node (via `ssh artemis '...'` or a project's `./hpc sh`).

```bash
squeue -u $USER -o '%.10i %.12P %.28j %.8T %.12M %.12L %R'   # my jobs
squeue -u $USER -h -t RUNNING -o '%C' | awk '{s+=$1} END {print s}'   # CPUs I hold (vs 550)
squeue -p sussexneuro -o '%.10i %.10u %.8T %.5C %.12L'      # who holds the group pool
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,MaxRSS,NodeList
scontrol show job <jobid> | grep -E 'QOS|Reason|NodeList'
sprio -u $USER                                              # my priority breakdown
sacctmgr -nP show qos format=Name,GrpTRES,MaxTRESPU,MaxWall # the quotas above
sacctmgr -nP show assoc user=$USER format=Account,Partition,QOS
id -Gn                                                      # my Unix groups
lfs quota -h -u $USER /mnt/lustre                           # Lustre usage vs quota
```

`sacct` reports `MaxRSS` as the maximum over processes, not the sum: with
several chains per task it shows one chain.

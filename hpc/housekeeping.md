# Housekeeping — keeping our cluster storage lean

Artemis storage is finite (2 TB and ~4 million files per user on Lustre),
**not backed up**, and partly purgeable (scratch). The goal is that every
file on the cluster is either *in use*, *expensive to recreate and still
needed*, or *gone*.

- [Layout conventions](#layout-conventions) — where things go, so audits are easy
- [What to keep, what to delete](#what-to-keep-what-to-delete)
- [When to tidy](#when-to-tidy)
- [How to run an audit](#how-to-run-an-audit)
- [Long-term homes](#long-term-homes)

---

## Layout conventions

One account, many projects:

```
~/                                             home: small, backed up
  .cmdstan/cmdstan-<ver>/                      CmdStan (+ ~800 MB per .gch variant)
/mnt/lustre/users/<group>/<user>/              2 TB, NOT backed up
  cluster_R_libs/x86_64-pc-linux-gnu-library/<R ver>/   shared R library
  <Project>/                                   one dir per project (driver-managed)
    *.R  *.slurm                               mirrored by ./hpc push — never edit here
    models/                                    production shards
    models/combined/                           merged results (what gets pulled)
    models/estimates/, ...                     other derived outputs
    smoke_<YYYYMMDD>/                          throwaway test output — delete once recorded
    superseded_<what>_<YYYYMMDD>/              parked old results — delete at next audit
/mnt/lustre/scratch/<group>/<user>/<Project>/  job logs only; purgeable
```

Rules that make audits mechanical:

- **Throwaway output is named as such**: `smoke_*`, `test*`, `probe*`,
  `tmp*`. Anything else is presumed production.
- **Parked output carries a date**: `superseded_<what>_<date>/`. Moving
  results aside instead of deleting is fine for days, not months.
- **Logs live in scratch**, results never do.
- The project's own docs say which cluster directory it uses (e.g. IGC uses
  `IGComputational/`, FakeArt `FakeArt/`).

## What to keep, what to delete

| thing | keep while... | then | notes |
| --- | --- | --- | --- |
| smoke / test / probe dirs and their logs | the numbers are not yet written into the project docs | **delete** (same day is ideal) | never let them sit next to production outputs |
| 0-byte or partial files | never | **delete** | failed writes; they can be pulled over good copies |
| job logs (`.out`/`.err`) in scratch | the run's measurements are not yet recorded, or it failed and is being debugged | **delete** after ~30 days | scratch purges anyway; record REPORT lines first |
| shards (`models/*.rds`) | the model is still being analysed / could be re-combined (e.g. a different criterion) | **delete** once the combined fit is verified *and pulled/archived*, and the model is frozen (paper submitted, or superseded) | shards are hours–days of compute, so do not rush; but they are the bulk of our usage (~200 MB each) |
| combined fits | the project is active | archive to a [long-term home](#long-term-homes), then delete from the cluster at publication | the cluster is not an archive |
| superseded fits (old formula/data) | the replacement is not yet verified | **delete** | check nothing local still depends on them |
| old CmdStan versions in `~/.cmdstan` | any project still pins them | **delete** | home is small |
| unused `.gch` variants | a job might compile with those flags | optional delete (~800 MB each) | never while jobs are compiling; they are rebuilt on demand |
| R library | always | refresh, do not delete | shared by all projects on the account |
| a whole inactive project dir (no change > 6 months) | its owner says so | ask the owner, archive, delete | |

When in doubt, **keep and ask** — nothing on Lustre can be recovered.

## When to tidy

| trigger | what |
| --- | --- |
| end of every smoke test | delete its directory and logs once numbers are recorded |
| end of every production batch | "post-run tidy": stubs, superseded outputs, test dirs, logs of that batch |
| **every ~3 months** | full audit with [scripts/audit.sh](scripts/audit.sh), logged |
| Lustre usage > 50% of 2 TB, or file count > 2 M | full audit now |
| a paper is submitted / a project is frozen | archive combined results, delete shards |

## How to run an audit

1. **Run the read-only audit** from any machine with SSH set up (VPN on):

   ```bash
   bash hpc/scripts/audit.sh                  # defaults: alias artemis, 30-day age threshold
   bash hpc/scripts/audit.sh --days 60        # different "old" threshold
   ```

   It opens **one** SSH connection, reads, and deletes nothing. It reports:
   quota usage; size, file count and last change per project dir (users and
   scratch); CmdStan versions and `.gch` variants; the R library; files over
   1 GB; throwaway-named dirs; 0-byte `.rds`; shards that sit next to a
   combined fit; scratch files older than the threshold.

2. **Classify** each finding with the table above into *delete*, *archive
   then delete*, *keep*, or *ask*. An agent writes this as a proposal, with
   sizes, and does not act on it.
3. **Get explicit approval** from the account owner for the exact list.
4. **Act**, preferring precise paths over globs, and re-run the audit to
   confirm the result.
5. **Log it** in your gitignored `hpc/private/audit-log.md`: date, usage
   before → after, what was deleted or archived (and where), what was kept
   and why, what to revisit. Next audit starts by reading the last entry.

Log entry template:

```markdown
## 2026-12-15 — dmm56 (quarterly)
- Lustre users: 1.20 TB / 2 TB, 310k files → 0.62 TB, 180k files
- Deleted: FakeArt/models/smoke2/ (0.4 GB); IGComputational/tests/ (12 GB); 0-byte stubs (3)
- Archived then deleted: FakeArt shards (41 GB) — combined fits on OneDrive /Lab/FakeArt/models/
- Kept: IGComputational/models/ gam_* shards — models still being compared
- Revisit: IGC shards after the paper is submitted
```

## Long-term homes

Lustre is not backed up and scratch is purged, so results worth keeping must
also live elsewhere. Options, as of 2026-09-22:

- **Sussex OneDrive / SharePoint** — backed up, large, easy to share with
  Sussex colleagues. The default for combined fits.
- **The project's public archive (OSF, Zenodo, ...)** at publication, for
  anything that belongs with the paper.
- **The project repo** only for *small* derived results (tables, estimates);
  not for fits.
- **Local Dropbox** is a working copy, not an archive — and large fits there
  cost everyone's sync. Keep `analysis/models/` out of Dropbox sync if the
  notebooks no longer read the fits.
- Avoid ResearchData (the old R: drive): Artemis docs list it as end-of-life
  and closed to new data. Bulk Storage exists (paid, ~£120/TB, restores
  limited to 8–12 months) and is only worth it for very large datasets.

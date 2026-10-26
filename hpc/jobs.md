# Jobs — writing, sizing, submitting, monitoring, collecting

How we run work on Artemis. The examples use our Bayesian-fit layout
(one array job per model, one shard per task), but the rules are general.

- [The .slurm script](#the-slurm-script)
- [Wall time](#wall-time)
- [Sizing](#sizing) — CPUs, threads, memory
- [Choosing a partition](#choosing-a-partition)
- [Submitting](#submitting)
- [Test runs](#test-runs)
- [Resuming and stale outputs](#resuming-and-stale-outputs)
- [Monitoring](#monitoring)
- [Verifying outputs](#verifying-outputs)
- [Collecting results](#collecting-results)
- [Splitting work across accounts](#splitting-work-across-accounts)
- [Sharing results between accounts](#sharing-results-between-accounts)

---

## The .slurm script

Keep `.slurm` files generic: nothing account-specific, everything passed by
`sbatch --export` / command-line flags from the project driver. Required
pieces, each learned from a failed run:

```bash
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --partition=general
#SBATCH --mail-type=END,FAIL
# no --time: see "Wall time"

PROJECT_DIR="${XX_USERS_DIR:-$SLURM_SUBMIT_DIR}"
cd "$PROJECT_DIR" || exit 1
echo "Running on $(hostname) at $(date '+%F %T')"

# 1. 'module' is undefined in a batch shell
[ -n "${LMOD_CMD:-}" ] || [ ! -f /etc/profile.d/lmod.sh ] || . /etc/profile.d/lmod.sh
# 2. compute nodes cannot see the EasyBuild tree unless told
module use "${XX_EB_MODULES:-/mnt/shared/easybuild/modules/all}"
module load "${XX_R_MODULE:-CmdStanR/0.7.1-foss-2023a-R-4.3.2}"
# 3. project library first, so it shadows the module
[ -z "${XX_R_LIBS:-}" ] || export R_LIBS="${XX_R_LIBS}${R_LIBS:+:$R_LIBS}"
# 4. brms 2.21.0, whatever the account (toolchain.md#the-brms-trap)
export R_LIBS_USER="${XX_R_LIBS_USER:-/research/cisc2/shared/cluster_R_libs/x86_64-pc-linux-gnu-library/4.2/}"
Rscript -e 'cat("brms", format(packageVersion("brms")), "from", find.package("brms"), "\n")'

Rscript fit_model.R
status=$?                       # 5. propagate R's exit status
echo "FINISHED at $(date '+%F %T') with status $status"
exit $status
```

- **Exit status**: a trailing `echo` made every crashed task report
  `COMPLETED 0:0` in `sacct`. Capture `$?` and `exit` with it; never add a
  command after `Rscript` without preserving it.
- **Line endings**: a CRLF `.slurm` fails with `bad interpreter`. Force LF in
  `.gitattributes` (`*.slurm`, `*.sh`, the driver, cluster-side `*.R`) and
  strip `\r` on push.
- `XX_` is the project's variable prefix (`IGC_`, `FA_`, ...), so two
  projects can be driven from the same shell.
- **Seed CmdStan, not R**: pass `seed =` to `brm()` / `$sample()`, and never
  `set.seed()` before fitting in an array task (`set.seed(NULL)` after
  drawing anything that needs it). Tasks that seed R alike can kill each
  other's chains ([troubleshooting.md#chains-killed-by-a-sibling-task](troubleshooting.md#chains-killed-by-a-sibling-task)).

## Wall time

**Do not set `--time`; choose the partition.** Every partition's default is
its maximum ([artemis.md#partitions](artemis.md#partitions)), trimming the
request does not speed dispatch here, and a task killed at the wall loses
everything it had not saved — for Stan, the **whole chain**, since it cannot
checkpoint mid-run.

On 2026-09-20, IGC fits submitted with `--time=2-00:00:00` (reasoned from a
12–20 h projection) measured 42.7–44 h and the rest were about to be killed.
**For a job whose runtime is a projection rather than a measurement, use the
partition's maximum.** The only exception worth making is a bounded `--time`
on a *shared* pool (`sussexneuro`) when you have measured headroom, so an
overrun does not tie up colleagues' allowance.

## Sizing

- **Measure memory once, then size to it.** `sacct -j <id>
  --format=JobID,MaxRSS` after a representative run. Memory is usually
  dominated by a fixed overhead (R, packages, compiled model) plus a small
  per-row term, so scaling a toy run's total gives wildly wrong answers — fit
  the two terms from two or three sizes. Over-requesting delays dispatch.
- **Threads per chain beat chains per task** for brms/Stan (`threading()`
  scales nearly linearly; 4 chains × 4 threads bought nothing over 2 × 8).
- **One chain per task** (all threads to it) halves per-chain wall, but a
  chain that dies at initialisation takes the whole task. Two chains per task
  is the safer default until inits are proven at scale.
- **Probe runtime at production warmup.** A short warmup is a valid shortcut
  for measuring memory and a trap for measuring time: unadapted chains run at
  max treedepth and produce bogus (e.g. "superlinear") scaling.
- **Many short chains do not beat few long ones** when warmup dominates:
  warmup is paid per chain, so halving draws per chain doubles the warmup
  bill, and chains that never reached the typical set pool into confidently
  wrong posteriors.
- Array widths of everything running at once should add up to the
  partition's concurrency, `floor(cap / cpus-per-task)`.

## Choosing a partition

1. Measured runtime comfortably < 2 h → `short`; < 8 h → `general` (400 CPUs).
2. Longer, or unmeasured and possibly longer → `long` (8 days, 140 CPUs).
3. `long` full, or the job must run alongside another project's arrays →
   `sussexneuro` (check the pool first; [artemis.md#sussexneuro](artemis.md#sussexneuro)).
4. Pending with `QOSMaxCpuPerUserLimit` everywhere → you are at the account's
   550 CPUs; switching partition will not help. Wait, or use a second account.

`verylong` (30 days, 70 CPUs) is almost never worth it.

## Submitting

- Submit through the project driver (`./hpc fit <model>`), which validates
  the name against the project's registry before anything reaches the queue —
  a typo should fail in a second, not eight hours in.
- **One SSH connection per batch of submissions.** Build the `sbatch` lines
  into one script and send it once; suffix each with `|| echo 'SUBMIT FAILED'`
  and prefix it with its name so one rejection is visible and does not stop
  the rest. A local `for m in ...; do ./hpc fit $m; done` loop trips the sshd
  rate limit and silently drops submissions.
- **Push mirrors, not merges.** Top-level scripts on the cluster that no
  longer exist locally are deleted on push, so a renamed script cannot be
  submitted by accident. Never edit code on the cluster.
- **Data**: jobs that read data from GitHub raw URLs fit whatever is on
  `main` — commit and push data before submitting, or the job silently fits
  the previous version.
- For a burst of I/O-heavy jobs (e.g. many combines reading the shared R
  library), chain them with `--dependency=afterany:<jobid>` rather than
  starting them all at once.

## Test runs

- **Every test or probe gets its own output directory**
  (`XX_MODELS_DIR=.../smoke_<date>`). With resumable outputs
  (`file_refit = "never"`), a test shard left in the production directory is
  silently adopted by the production run.
- A smoke test is tiny data, a short warmup, `--partition=short`, few CPUs:
  `XX_NPARTICIPANTS=20 XX_WARMUP=300 XX_SAMPLES=100 ./hpc fit <model>
  --array=1-2 --partition=short --cpus-per-task=8 --mem=16G`.
- Record the numbers in the project docs, then **delete the test directory
  and its logs** the same day ([housekeeping.md](housekeeping.md)).

## Resuming and stale outputs

Stan cannot checkpoint, but an array can: each task writes its own shard, and
with `brm(..., file = ..., file_refit = "never")` a resubmitted array skips
shards that exist. The price: **a shard on disk is reused even if the formula
or data changed.** A changed model or dataset needs a fresh output directory
or `XX_FILE_REFIT=always`. (`file_refit = "on_change"` is brms's middle way.)
Shard ids need not be contiguous; what matters is the total chain count.

## Monitoring

### Status reports

When the user just asks "how are the jobs doing?", the answer is always the
same shape — not a log dump, and not only `squeue`. Gather it in **one or two
SSH calls**:

```bash
./hpc queue                  # STATE, TIME (elapsed), TIME_LEFT, reason if PENDING
./hpc progress <model>       # latest 'Chain N Iteration:' per chain + REPORT + errors
# start times, if the driver's queue format lacks them:
./hpc sh "squeue -u \$USER -o '%.14i %.12P %.28j %.8T %.20S %.12M %.12L %R'"
```

(If a project lacks `progress`:
`./hpc sh "grep -h 'Iteration\|REPORT' <scratch>/fit_<model>_*.out | tail -40"`.)

**The report contains:**

1. **Is it running, and since when.** Per job/array task: state; for
   `RUNNING`, the start time and elapsed time (and node, if it matters); for
   `PENDING`, the reason (`Priority`, `Resources`, `QOSMaxCpuPerUserLimit`, a
   dependency) and, for a CPU-limit reason, whether it is the partition cap or
   the account's 550 ([artemis.md#quotas](artemis.md#quotas)). Finished or
   failed tasks since the last check: exit state from `sacct`, and the
   `REPORT` line or the error.
2. **Progress, per chain per shard**, as a table: latest iteration / total,
   percent, and phase (warmup or sampling).
3. **ETA**, extrapolated per chain, rolled up to the shard (its slowest
   chain) and to the model (its slowest shard, plus a further wave if some
   of its tasks are still pending behind the CPU cap).
4. **Wall-time risk.** Compare each shard's projected finish with its
   `TIME_LEFT`. Flag **at risk** when the ETA exceeds ~80% of the time left,
   and **will not finish** when it exceeds all of it — and say what that
   costs (Stan cannot checkpoint: a killed task loses its whole chain) and
   the options (let it run and resubmit the shard; cancel early and resubmit
   on a longer partition; reduce draws for the resubmission).

Template:

```markdown
**gam_lnr** — array 11385713, `long`, 4 tasks running since 2026-09-18 14:02 (1 d 6 h ago)

| shard | node | elapsed | chain | iteration | phase | % | shard ETA | time left | risk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | a40-03 | 30.1 h | 1 | 1200 / 1500 | sampling | 80% | ~8 h | 6.7 d | ok |
|   |        |        | 2 | 1100 / 1500 | sampling | 73% |      |       |    |
| 2 | a40-16 | 30.1 h | 1 | 700 / 1500 | warmup | 47% | ~35 h | 6.7 d | ok |
|   |        |        | 2 | 600 / 1500 | warmup | 40% |      |       |    |

Model ETA: ~35 h (shard 2 is the straggler). Nothing near the wall.
```

**How to extrapolate** (rough is fine; say it is rough):

- rate = iterations done ÷ (elapsed − ~1–5 min of compile time); remaining
  time = (total − done) ÷ rate. Chains in one shard run in parallel, so the
  shard finishes with its slowest chain.
- **Early warmup is slower than the rest** (the first ~100–150 iterations run
  at max treedepth on a cold start), so an ETA taken during early warmup is
  pessimistic, and one taken during sampling is the most reliable. Say which
  phase the estimate is based on.
- If a project documents a measured per-iteration cost for that model
  (`s/iter`, a previous `REPORT` wall), prefer it over a guess and cite it.
- cmdstanr refreshes its progress line sparsely, so the latest line can be
  hours old; the true count is at least what is shown. When the estimate
  hinges on it, also give the `.out` file's modification time.
- Node placement changes speed 2–3×, so shards of one model on different
  nodes can have very different ETAs; that is not by itself a problem.

- Have every job print **one summary line** at the end (e.g. `REPORT <model>
  | wall | n_leapfrog | treedepth | stepsize | divergent | max Rhat | min
  neff_ratio`) so runs can be compared without downloading outputs.
- No new `Iteration` line for hours is **not** a hang: cmdstanr spaces its
  console refresh through the run. Trust `TIME` climbing in `squeue`.
- Judge convergence on the **combined** fit, not per shard: a 2-chain shard's
  Rhat over thousands of parameters is noisy and lands on the worst one.
- Take wall time from the logs (`REPORT`, `sacct Elapsed`), not from a
  combined brms fit — `combine_models()` keeps only the first shard's timing.

## Verifying outputs

A clean exit is not proof of a complete result.

- **Count what you expect**: a combined fit should have
  `shards × chains per shard` chains (`brms::nchains()`) and the matching
  draw count. Merges silently accept missing chains; five fits were once
  found short this way. cmdstanr itself drops a chain it did not see finish
  and renumbers the rest, so a shard can be short with no error at all
  ([troubleshooting.md#chains-killed-by-a-sibling-task](troubleshooting.md#chains-killed-by-a-sibling-task)).
- **Zero-byte or partial files** can be left behind by a failed write (and a
  failed `saveRDS` can bump the mtime of the previous file without changing
  it). Only the job's own "wrote ... with N draws" line proves success.
  Find stubs with `find <dir> -size 0 -name '*.rds'`.

## Collecting results

- Pull combined results, not raw shards.
- **Never `scp` straight into a Dropbox folder.** Dropbox holds files open
  while uploading, `scp` then truncates and fails mid-write, and the partial
  `.rds` still loads far enough to look plausible (nine fits were truncated
  this way on 2026-09-21). Pull into a staging dir outside Dropbox, compare
  byte sizes with the cluster, then move into place (FakeArt's `cmd_pull` is
  the reference implementation). Skip `scp -p` inside Dropbox.
- Moving or deleting a file on the cluster does not un-pull the local copy —
  check local files against the cluster by size, not by assumption.
- Prefer small derived results (estimates, summaries) over whole fits when
  that is all the analysis needs: compute them on the cluster and pull
  megabytes, not gigabytes. Strip attached model objects before saving (easystats
  attaches the full fit to every `estimate_*()` result; formulas carry their
  environment).

## Splitting work across accounts

CPU quotas are per account, so a colleague with their own account and a clone
of the project repo can fit other models at the same time. The model
registry travels in git; only the account is local (`hpc.local`). Any model
either account fits must be **defined and committed** in the shared registry.
Agree who fits what; `./hpc queue` on each side answers who is running what
now. Stack with `sussexneuro` for a third allowance.

## Sharing results between accounts

Nobody can read another account's directories ([artemis.md#storage](artemis.md#storage)),
so whoever fitted a model combines it, pulls it, and **sends the file**:

- combined fits run ~0.2–1 GB; `.rds` is already gzipped, so zipping again
  buys nothing;
- use **Sussex OneDrive** when both ends are Sussex (no expiry, no size limit
  that matters), or a transfer service such as MyAirBridge (20 GB free).

Alternatively the owner can open a traversal path with
`chmod o+x /mnt/lustre/users/<group>/<them>` (execute-only, not listable;
revert with `chmod o-x`) so the other can `scp` from a known path. It is a
permission change on their account: theirs to make.

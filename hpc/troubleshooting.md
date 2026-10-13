# Troubleshooting — symptom → cause → fix

Search this page for the error text you see. Each entry was hit at least once
on Artemis. Add new ones in the same shape, with the date.

| symptom (search for) | jump to |
| --- | --- |
| `cannot reach artemis`, SSH timeout | [Cannot connect](#cannot-connect) |
| `kex_exchange_identification: read: Connection reset` | [SSH connection reset](#ssh-connection-reset) |
| `module(s) exist but cannot be loaded`, `Rscript: command not found`, `module: command not found` | [Module errors in a job](#module-errors-in-a-job) |
| `bad interpreter: No such file or directory` | [Bad interpreter](#bad-interpreter) |
| `while reading precompiled header: No such file or directory` | [Precompiled header race](#precompiled-header-race) |
| Stan compile error on **every** model, `int[]` syntax, `reduce_sum` template errors | [Every model fails to compile](#every-model-fails-to-compile) |
| `invalid 'y' type in 'x && y'` reading CmdStan output | [Old cmdstanr](#old-cmdstanr) |
| `Package collapse is installed, but package version ... is required` | [Version floor not met](#version-floor-not-met) |
| `Rejecting initial value`, `Gradient evaluated at the initial value is not finite` | [Chains die at initialisation](#chains-die-at-initialisation) |
| fewer chains than requested and no error, `finished unexpectedly`, exit status `-9`, `No chains finished successfully` with nothing on stderr | [Chains killed by a sibling task](#chains-killed-by-a-sibling-task) |
| `PENDING (QOSMaxCpuPerUserLimit)` | [Pending on CPU limit](#pending-on-cpu-limit) |
| `QOSGrpCpuLimit` at submission | [Rejected on sussexneuro](#rejected-on-sussexneuro) |
| `User's group not permitted to use this partition` | [No sussexneuro access](#no-sussexneuro-access) |
| `Input/output error`, `seek failed on .../*.rdb`, 0-byte `.rds` | [Input/output error](#inputoutput-error) |
| `sacct` says `COMPLETED 0:0` but the job clearly failed | [Failures reported as completed](#failures-reported-as-completed) |
| results look like an old model / wrong data | [Stale outputs adopted](#stale-outputs-adopted) |
| local `.rds` truncated, `ftruncate ... Permission denied` | [Truncated pulls](#truncated-pulls) |
| no new iteration lines for hours | [Looks hung](#looks-hung) |

---

### Cannot connect

**Cause**: VPN down (most often), or the key is not in
`~/.ssh/authorized_keys` on the cluster.
**Fix**: connect GlobalProtect (`bond.sussex.ac.uk`) and retry once. Still
failing → `ssh -v artemis true` and check which key is offered; re-run
[setup.md#a-new-machine](setup.md#a-new-machine). An agent should ask the
user to connect the VPN rather than retry.

### SSH connection reset

`kex_exchange_identification: read: Connection reset` while DNS still
resolves. **Cause**: sshd rate-limits bursts of connections — not the VPN.
Triggered by loops that open one connection per file or per job.
**Fix**: wait ~2 minutes. Then batch the work into one connection (tar pipe,
heredoc, server-side loop). Check which submissions in a burst were lost:
missing job IDs in the output.

### Module errors in a job

**Cause**: batch shells lack the `module` function, and compute nodes do not
have the EasyBuild tree on `MODULEPATH`.
**Fix**: source `/etc/profile.d/lmod.sh`, then
`module use /mnt/shared/easybuild/modules/all`, then `module load`
([jobs.md#the-slurm-script](jobs.md#the-slurm-script)).

### Bad interpreter

**Cause**: CRLF line endings in a `.slurm` or `.sh` file (edited on Windows).
**Fix**: `.gitattributes` with `eol=lf` for cluster-side files, and strip
`\r` on push. On the cluster: `sed -i 's/\r$//' file.slurm`.

### Precompiled header race

A cold array where most tasks die within ~3 minutes at compile time.
**Cause**: the needed `.gch` variant was absent and every task raced to
build it; losers leave a corrupt variant.
**Fix**: `rebuild_cmdstan(cores = 8)` inside `srun`, then `./hpc precompile`,
then resubmit. Details: [toolchain.md#precompiled-header](toolchain.md#precompiled-header).

### Every model fails to compile

On a fresh account, within ~40 s of `sbatch`. **Cause**: the account is not
getting the brms the working account gets (the working one borrows it from a
third-party library through `R_LIBS_USER`).
**Fix**: see [toolchain.md#the-brms-trap](toolchain.md#the-brms-trap).
Suspect this first whenever a failure is environment-wide rather than
model-specific.

### Old cmdstanr

**Cause**: the module's cmdstanr 0.7.1 is being used; it cannot read CmdStan
≥ 2.36 output. **Fix**: install a current cmdstanr (from
`https://stan-dev.r-universe.dev`) into the project library and check it
precedes the module on `R_LIBS`.

### Version floor not met

**Cause**: an older copy of a package (from the module) is present, so the
installer thought it was satisfied. **Fix**: `./hpc install <pkg>` to force
it into the project library; make the installer check the floor
([toolchain.md#the-project-r-library](toolchain.md#the-project-r-library)).

### Chains die at initialisation

**Cause** (seen with cogmod ≤ 0.3.2, rate grew with data size): explicit
inits are used verbatim, so one bad start is fatal rather than retried;
root cause was a non-finite tail gradient, fixed in cogmod 0.3.3.
**Fix**: check the cogmod version in the job log. With one chain per task a
single rejection loses the task — two chains per task limits the damage.
Resubmit the lost shard under a new id.

### Chains killed by a sibling task

Chains vanish mid-run, SIGKILLed (exit status `-9`), with nothing on stderr,
and only in array tasks that share a node. **Cause** (2026-10-13, cogmod
benchmarks; 16 and 20 of 96 chains in two arrays): processx below 3.9, which
the module ships (3.8.2), tags every process cmdstanr starts with an id drawn
from R's RNG plus the current second, and when `$sample()` returns cmdstanr's
cleanup SIGKILLs every process on the node carrying its tags. Two tasks that
`set.seed()` the same value before fitting, and start sampling on one node in
the same second, share tags, and the first to finish kills the other's running
chains. Different models are not safe from each other: after the same
`set.seed()` their tags are the same sequence, shifted. cmdstanr then drops
the killed chains and renumbers the rest 1..k, so the fit is just short; with
every chain killed it stops with `No chains finished successfully`.
`brm(seed = )` and `$sample(seed = )` seed CmdStan only, and an R session that
never calls `set.seed()` seeds itself from the clock and its process id: our
production `fit_model.R`s do this and are not exposed.
**Fix**: no `set.seed()` before fitting in an array task. If starting values
must be drawn reproducibly, draw them, then `set.seed(NULL)` before `brm()` /
`$sample()` — CmdStan's own seed still makes the draws reproducible. Or put
processx ≥ 3.9 (tag from `tempfile()`, not the RNG) in the project library.
**Check**: `brms::nchains()` against what was requested, and
`fit$return_codes()` when driving cmdstanr directly.

### Pending on CPU limit

**Cause**: either the partition's per-user cap or the account-wide 550-CPU
cap — the message is identical. **Fix**: sum your running CPUs
(`squeue -u $USER -h -t RUNNING -o '%C' | awk '{s+=$1} END {print s}'`).
Under 550: the partition is full — another partition may start it now. At or
over 550: nothing will start anywhere; wait
([artemis.md#quotas](artemis.md#quotas)).

### Rejected on sussexneuro

**Cause**: request exceeds the group's free share of 256 CPUs; `DenyOnLimit`
rejects instead of queueing. **Fix**: check the pool
(`squeue -p sussexneuro -o '%.10i %.10u %.5C'`), shrink the request or wait,
and resubmit by hand.

### No sussexneuro access

**Cause**: not in the `artemis_sussexneuro` Unix group. **Fix**: ask the PI /
IT to be added; verify with `id -Gn` and a bare `sbatch -p sussexneuro`.

### Input/output error

`gzfile(...) cannot open the connection ... Input/output error`, `seek failed
on .../cogmod.rdb`, or a 0-byte output. Seen on `artemis-rtx-00`, 2026-09-22,
when several jobs hit the Lustre-backed R library at once.
**Fix**: do not debug R. Delete any 0-byte stub, resubmit with
`--exclude=artemis-rtx-00`, and stagger bursts with
`--dependency=afterany:<jobid>`. Only the job's own success line proves the
retry worked — an existing file with a fresh mtime does not.

### Failures reported as completed

**Cause**: the `.slurm` ended with a command after `Rscript` that exited 0.
**Fix**: propagate `$?` ([jobs.md#the-slurm-script](jobs.md#the-slurm-script)).

### Stale outputs adopted

**Cause**: `file_refit = "never"` reuses an existing shard even if the
formula or data changed; or a test shard sat in the production directory; or
the job read data from GitHub `main` before the new data was pushed.
**Fix**: fresh output directory or `XX_FILE_REFIT=always`; separate test
directories; push data first ([jobs.md#resuming-and-stale-outputs](jobs.md#resuming-and-stale-outputs)).

### Truncated pulls

**Cause**: `scp` into a Dropbox-synced folder while Dropbox holds the file.
**Fix**: pull via a staging directory outside Dropbox and verify sizes
([jobs.md#collecting-results](jobs.md#collecting-results)).

### Looks hung

**Cause**: usually nothing — cmdstanr's console refresh is sparse, and full
data warmup can take many hours before the next line. **Check**: `TIME`
climbing in `squeue` and the task not requeued. Only then read the full log.

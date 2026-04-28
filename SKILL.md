---
name: autoresearch-optimize
description: >
  Autonomous parameter/code optimization loop for any project with a benchmark
  and evaluation script. Use when the user asks to run autoresearch, optimize
  parameters, tune a model, run experiments, or improve performance metrics
  (BIC, accuracy, latency, etc.) through systematic trial-and-error with
  automatic KEEP/DISCARD decisions. Also use when the user wants to resume a
  previous optimization session or plan a new wave of experiments.
---

# Autoresearch Optimize

Autonomous optimization loop: propose change -> benchmark -> evaluate -> KEEP or DISCARD -> repeat.

This skill implements key strategies from the autoresearch community:
- **Failure-driven experiment planning**: analyze failures/weaknesses of previous runs to propose targeted changes
- **Multi-run variance control**: adapt measurement protocol to the runtime profile (compiled, interpreted, hybrid)
- **Structured experiment log**: append-only TSV for reliable resume and analysis across sessions
- **Baseline warmup protocol**: ensure baseline and experiments are measured under identical conditions

## Prerequisites

Before starting, verify the project has:

1. **Benchmark script** that outputs a `METRIC_JSON` marker followed by a JSON line:
   ```
   METRIC_JSON
   {"primary":-2825.5,"time_s":11.84,"success":true,...}
   ```
   The JSON must contain at minimum: `success` (bool) and the primary metric.

2. **Evaluate script** that compares benchmark output to a baseline:
   ```bash
   ./benchmark/evaluate.sh benchmark/baseline.json /tmp/result.txt
   # Exit 0 = KEEP, Exit 1 = DISCARD, Exit 2 = ERROR
   ```

3. **Baseline file** (`benchmark/baseline.json`) with the current best metrics.

4. **Clean git state** -- all changes committed, no dirty working tree.

If the baseline file is missing, create it using the benchmark helper script:
```bash
bash ~/.forge/skills/autoresearch-optimize/scripts/run_bench.sh init-baseline benchmark/baseline.json
```

## Runtime Profiles

The skill adapts its measurement strategy based on the runtime profile of the language/toolchain. **The profile is auto-detected from the benchmark script extension, but can be overridden.**

### Profile: `compiled` (C, C++, Rust, Go, Fortran)

Characteristics: deterministic timing, no warmup needed, low variance.

| Setting | Value |
|---------|-------|
| Warmup runs | 0 |
| Measured runs | 1 |
| Confirmation runs | 1 (only if delta < 3%) |
| Time variance | Low (~1-2%) |
| Detection | `benchmark.c`, `benchmark.cpp`, `benchmark.rs`, `benchmark.go`, `benchmark.f90`, or `Makefile` with `benchmark:` target |

### Profile: `hybrid` (Julia, Java, C#)

Characteristics: JIT compilation on first run, warmup essential, moderate variance after warmup.

| Setting | Value |
|---------|-------|
| Warmup runs | 1 (full benchmark run, discarded) |
| Measured runs | 1 (second run, kept) |
| Confirmation runs | 1 (only if delta < 3%) |
| Time variance | Moderate (~5-10% after warmup) |
| Detection | `benchmark.jl`, `Benchmark.java`, `Benchmark.cs` |

### Profile: `interpreted` (Python, R, Ruby, MATLAB)

Characteristics: no JIT, variable timing due to GC/scheduling, moderate variance.

| Setting | Value |
|---------|-------|
| Warmup runs | 0 (or 1 if the optimizer caches state) |
| Measured runs | 1 (or 3 with median if stochastic optimizer) |
| Confirmation runs | 1 (only if delta < 3%) |
| Time variance | Moderate (~3-8%) |
| Detection | `benchmark.py`, `benchmark.R`, `benchmark.rb`, `benchmark.m` |

### Profile: `stochastic`

When the optimizer itself is stochastic (e.g., random seed, evolutionary algorithm), the results vary between runs regardless of language. In this case:

| Setting | Value |
|---------|-------|
| Warmup runs | per language profile |
| Measured runs | 3 (take median) |
| Confirmation runs | 0 (median of 3 is already robust) |
| Time variance | High (depends on convergence path) |

Detection: check if the benchmark script uses a fixed seed. If not, assume stochastic.

### Overriding the profile

If auto-detection is wrong, set the profile explicitly:
```bash
export AUTORESEARCH_PROFILE=compiled
```
Or tell the agent: "This project uses the compiled profile."

## Decision Logic

The default KEEP/DISCARD rule (adjust per project via `evaluate.sh`):

```
KEEP if:
  - Primary metric improved by > 2%
  OR
  - Primary metric stable within +/-2% AND time improved by > 15%

DISCARD otherwise (crash = auto-DISCARD)
```

If the project has an `evaluate.sh`, it encodes this logic. Otherwise, implement it manually.

### Variance-Aware Acceptance

A single benchmark run can be misleading. The measurement protocol depends on the runtime profile:

1. **Run the warmup** (per profile: 0 for compiled, 1 for hybrid, 0 for interpreted).
2. **Run the measured run** (per profile: 1 for compiled/hybrid, 1-3 for interpreted/stochastic).
3. **Evaluate against baseline** using the measured run result.
4. **Confirmation**: if the primary metric delta is between 2-3% (marginal, close to threshold), run one additional confirmation before KEEPing. This prevents false KEEP from variance.

### Baseline Warmup Protocol

The baseline must be measured under the **same conditions** as experiments. If experiments use warmup runs, the baseline must too.

**Rule**: whenever the baseline is created or updated, use the same measurement protocol as experiments (same warmup count, same run count).

The `run_bench.sh` script handles this automatically -- it applies the same warmup protocol for both baseline creation and experiment measurement.

## Workflow

### Phase 0: Read Project Context

1. Read `program.md` if it exists -- it defines the optimization axes and constraints.
2. Read `autoresearch_log.md` if it exists -- it contains history of previous experiments.
3. Read `benchmark/experiments.tsv` if it exists -- structured log of all experiments.
4. Read the main source file to understand current parameter values.
5. Read `benchmark/baseline.json` to know the current baseline metrics.
6. **Detect runtime profile** from benchmark script extension (see Runtime Profiles).
7. **Failure analysis**: If previous experiments exist, identify patterns:
   - Which parameters have been tried and failed? (avoid repeating)
   - What was the closest to KEEP? (fine-tune around that value)
   - Are there systematic weaknesses? (e.g., always losing on time, or metric plateau)

### Phase 1: Plan Wave (Failure-Driven)

Plan a wave of 6-10 experiments. **The first 2-3 experiments should target the most promising changes based on failure analysis of previous waves.**

Prioritize by expected leverage:
1. **HIGH**: Algorithm/solver changes
2. **HIGH**: Constraint/bounds parameters
3. **MEDIUM**: Hyperparameters (tolerances, iteration counts)
4. **LOW**: Micro-optimizations (vectorization, compiler flags)

**Failure-driven planning strategy:**
- If previous wave had experiments that were close to KEEP (within 1% of threshold), prioritize fine-tuning those parameters.
- If all experiments in the previous wave degraded the primary metric, the parameter space is likely at a local optimum -- try algorithmic changes instead.
- If experiments degraded time but not quality, explore speed-focused changes (fewer iterations, looser tolerance, faster algorithm).
- Consult `references/anti-patterns.md` to avoid repeating known-bad changes.

For each planned experiment, record the parameter name, current value, proposed value, and rationale.

Use `todo_write` to track each experiment with status.

### Phase 2: Execute Experiments

For each experiment in the wave:

1. **Apply change** -- modify exactly one parameter/algorithm in the source file.
2. **Verify compilation** -- run a syntax check appropriate for the language:
   - Julia: `include("src/Module.jl")`
   - Python: `python -c "import module"`
   - Compiled: `make` or `cargo check`
3. **Run benchmark** -- use `run_bench.sh` which applies the correct measurement protocol for the runtime profile:
   ```bash
   bash ~/.forge/skills/autoresearch-optimize/scripts/run_bench.sh <exp_id> benchmark/baseline.json
   ```
   The script auto-detects the language, applies warmup, runs the measured benchmark, extracts metrics, evaluates against baseline, and logs to TSV.
4. **Evaluate** -- check exit code from `run_bench.sh` (0=KEEP, 1=DISCARD, 2=ERROR).
5. **Confirmation run** (if marginal): if primary metric delta is 2-3%, run one more time:
   ```bash
   bash ~/.forge/skills/autoresearch-optimize/scripts/run_bench.sh <exp_id>-confirm benchmark/baseline.json
   ```
   KEEP only if the confirmation run confirms the improvement.
6. **Decide**:
   - **KEEP**: `git commit` with descriptive message, update `benchmark/baseline.json`.
   - **DISCARD**: `git checkout` the source file to revert.
7. **Log** -- `run_bench.sh` auto-appends to `benchmark/experiments.tsv`. Also update `autoresearch_log.md` with narrative.
8. **Update todo** -- mark completed, add result summary.
9. **Adaptive planning**: if the experiment result reveals something unexpected (e.g., a parameter has no effect at all, or a huge effect in the wrong direction), adjust the remaining experiments in the wave accordingly. Do not blindly follow the original plan.

### Phase 3: Wave Summary

After all experiments in a wave:

1. Present a summary table: experiment, metric delta, time delta, verdict.
2. **Failure analysis for next wave**: identify the most promising directions for the next wave based on what was learned.
3. If >= 2 experiments were KEPT, plan a new wave (new parameters may interact).
4. If 0 experiments were KEPT across 2 consecutive waves, apply **plateau recovery** (see below).
5. Commit updated `autoresearch_log.md`.

### Plateau Recovery

When 2 consecutive waves produce 0 KEEP, do NOT immediately stop. Try these recovery strategies in order:

1. **Algorithmic reset**: switch to a fundamentally different optimizer algorithm.
2. **Constraint relaxation/expansion**: widen or narrow bounds by 20-30% on the most impactful constraint parameter.
3. **Interaction exploration**: test combinations of 2 parameters that were individually close to KEEP (breaking the "one change" rule intentionally, with justification).
4. **Data-driven**: analyze residuals/errors to identify systematic patterns that suggest missing model features.
5. **Declare true plateau**: if recovery also fails after 1 wave, the optimum is genuinely reached. Stop and document.

## Experiment Log Format

### `benchmark/experiments.tsv`

Append-only TSV file with one row per experiment. Auto-created and auto-appended by `run_bench.sh`.

Columns:
```
exp_id	timestamp	parameter	old_value	new_value	primary_delta	time_delta	metric2	metric3	metric4	verdict	commit_hash	runtime_profile
```

This file enables:
- Quick resume: `tail -20 benchmark/experiments.tsv` shows recent experiments
- Pattern analysis: `cut -f4,11 experiments.tsv | sort | uniq -c` shows which parameters are most often KEPT
- Failure analysis: `awk '$11=="DISCARD"' experiments.tsv | cut -f4 | sort | uniq -c` shows which parameters always fail

## Critical Rules

- **One change per experiment.** Never batch multiple parameter changes (except during plateau recovery, strategy 3).
- **Never modify files outside the optimization target.** If the project defines a scope, respect it.
- **Never `git checkout` files you didn't modify.** This destroys uncommitted work by others.
- **Always verify compilation** before running the benchmark.
- **Always revert on DISCARD.** The working tree must be clean before the next experiment.
- **Respect forbidden changes.** Read `program.md` for project-specific constraints.
- **Measure baseline and experiments identically.** Same warmup protocol, same run count, same conditions.

## Anti-Patterns to Avoid

See [references/anti-patterns.md](references/anti-patterns.md) for a catalog of changes that typically fail and should not be retried without strong justification.

## Benchmark Helper Script

See [scripts/run_bench.sh](scripts/run_bench.sh) for a reusable benchmark runner that:
- Auto-detects language and runtime profile
- Applies correct warmup protocol per profile
- Extracts METRIC_JSON and evaluates against baseline
- Auto-appends to `benchmark/experiments.tsv`

## Resume Protocol

To resume a previous optimization session:

1. Read `autoresearch_log.md` to understand what was tried.
2. Read `benchmark/experiments.tsv` for structured experiment history.
3. Do failure analysis: which parameters were closest to KEEP? Which direction was promising?
4. Read `benchmark/baseline.json` for the current baseline.
5. Verify git is clean.
6. Detect runtime profile from benchmark script.
7. Plan and execute a new wave, prioritizing failure-driven insights.

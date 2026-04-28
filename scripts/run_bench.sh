#!/usr/bin/env bash
# run_bench.sh — Run benchmark with runtime-profile-aware variance control.
#
# Usage:
#   ./scripts/run_bench.sh <exp_id> <baseline.json> [source_file]
#   ./scripts/run_bench.sh init-baseline <baseline.json>     # create baseline
#   ./scripts/run_bench.sh update-baseline <baseline.json>   # re-measure baseline
#
# Auto-detects the runtime profile from the benchmark script extension:
#   compiled:  .c, .cpp, .rs, .go, .f90, Makefile
#   hybrid:    .jl, .java, .cs
#   interpreted: .py, .R, .rb, .m
#
# Applies the correct warmup protocol per profile:
#   compiled:    0 warmup, 1 measured
#   hybrid:      1 warmup (discarded), 1 measured
#   interpreted: 0 warmup, 1 measured (or 3 with median if stochastic)
#
# Auto-appends results to benchmark/experiments.tsv
#
# Output:
#   /tmp/<exp_id>_result.txt   — full benchmark output (measured run)
#   /tmp/<exp_id>_warmup.txt   — warmup run output (if applicable)
#   /tmp/<exp_id>_metrics.json — extracted JSON metrics
#   Exit code from evaluate.sh (0=KEEP, 1=DISCARD, 2=ERROR)

set -euo pipefail

EXP_ID="${1:?Usage: run_bench.sh <exp_id> <baseline.json> [source_file]}"
BASELINE="${2:-benchmark/baseline.json}"
SOURCE_FILE="${3:-}"

RESULT_FILE="/tmp/${EXP_ID}_result.txt"
WARMUP_FILE="/tmp/${EXP_ID}_warmup.txt"
METRICS_FILE="/tmp/${EXP_ID}_metrics.json"
TSV_FILE="benchmark/experiments.tsv"

# ===========================================================================
# Detect benchmark command and runtime profile
# ===========================================================================

LANG="unknown"
PROFILE="interpreted"  # default safe profile
BENCH_CMD=""

if [ -f "benchmark/benchmark.jl" ]; then
    BENCH_CMD="julia --project=. benchmark/benchmark.jl"
    LANG="julia"
    PROFILE="hybrid"
elif [ -f "benchmark/benchmark.py" ]; then
    BENCH_CMD="python benchmark/benchmark.py"
    LANG="python"
    PROFILE="interpreted"
elif [ -f "benchmark/benchmark.R" ]; then
    BENCH_CMD="Rscript benchmark/benchmark.R"
    LANG="R"
    PROFILE="interpreted"
elif [ -f "benchmark/benchmark.rb" ]; then
    BENCH_CMD="ruby benchmark/benchmark.rb"
    LANG="ruby"
    PROFILE="interpreted"
elif [ -f "benchmark/benchmark.m" ]; then
    BENCH_CMD="matlab -batch \"run('benchmark/benchmark.m')\""
    LANG="matlab"
    PROFILE="interpreted"
elif [ -f "benchmark/benchmark.java" ]; then
    BENCH_CMD="java -cp benchmark Benchmark"
    LANG="java"
    PROFILE="hybrid"
elif [ -f "benchmark/benchmark.cs" ]; then
    BENCH_CMD="dotnet run --project benchmark"
    LANG="csharp"
    PROFILE="hybrid"
elif [ -f "benchmark/benchmark.rs" ]; then
    BENCH_CMD="cargo run --manifest-path benchmark/Cargo.toml --release"
    LANG="rust"
    PROFILE="compiled"
elif [ -f "benchmark/benchmark.cpp" ]; then
    BENCH_CMD="./benchmark/benchmark"
    LANG="cpp"
    PROFILE="compiled"
elif [ -f "benchmark/benchmark.c" ]; then
    BENCH_CMD="./benchmark/benchmark"
    LANG="c"
    PROFILE="compiled"
elif [ -f "benchmark/benchmark.go" ]; then
    BENCH_CMD="go run benchmark/benchmark.go"
    LANG="go"
    PROFILE="compiled"
elif [ -f "benchmark/benchmark.f90" ]; then
    BENCH_CMD="./benchmark/benchmark"
    LANG="fortran"
    PROFILE="compiled"
elif [ -f "Makefile" ] && grep -q "^benchmark:" Makefile; then
    BENCH_CMD="make benchmark"
    LANG="make"
    PROFILE="compiled"
else
    echo "ERROR: No benchmark command found."
    echo "Expected: benchmark/benchmark.{jl,py,R,rb,m,java,cs,rs,cpp,c,go,f90} or Makefile with benchmark target"
    exit 2
fi

# Allow profile override via environment variable
if [ -n "${AUTORESEARCH_PROFILE:-}" ]; then
    PROFILE="${AUTORESEARCH_PROFILE}"
fi

# ===========================================================================
# Special modes: init-baseline, update-baseline
# ===========================================================================

if [ "${EXP_ID}" = "init-baseline" ] || [ "${EXP_ID}" = "update-baseline" ]; then
    echo "=== ${EXP_ID}: measuring baseline with ${PROFILE} profile ==="
    echo "Command: ${BENCH_CMD}"

    # Apply warmup per profile
    if [ "${PROFILE}" = "hybrid" ]; then
        echo "--- Warmup run (discarded) ---"
        set +e
        ${BENCH_CMD} > "${WARMUP_FILE}" 2>&1
        WARMUP_EXIT=$?
        set -e
        if [ ${WARMUP_EXIT} -ne 0 ] && ! grep -q "METRIC_JSON" "${WARMUP_FILE}"; then
            echo "WARNING: Warmup failed (exit ${WARMUP_EXIT}), continuing anyway"
        fi
        echo "Warmup done."
    fi

    # Measured run
    echo "--- Measured run ---"
    set +e
    ${BENCH_CMD} > "${RESULT_FILE}" 2>&1
    BENCH_EXIT=$?
    set -e

    if [ ${BENCH_EXIT} -ne 0 ] && ! grep -q "METRIC_JSON" "${RESULT_FILE}"; then
        echo "ERROR: Benchmark crashed (exit ${BENCH_EXIT})"
        tail -20 "${RESULT_FILE}"
        exit 1
    fi

    METRICS=$(awk '/^METRIC_JSON$/{getline; print; exit}' "${RESULT_FILE}")
    if [ -z "${METRICS}" ]; then
        echo "ERROR: No METRIC_JSON found in output"
        exit 2
    fi

    echo "${METRICS}" > "${BASELINE}"
    echo "Baseline saved to: ${BASELINE}"
    echo "Metrics: ${METRICS}"
    exit 0
fi

# ===========================================================================
# Normal experiment mode
# ===========================================================================

echo "=== Experiment: ${EXP_ID} ==="
echo "Language: ${LANG}  |  Profile: ${PROFILE}"
echo "Running:  ${BENCH_CMD}"
echo "Output:   ${RESULT_FILE}"

# ===========================================================================
# Warmup (per profile)
# ===========================================================================

if [ "${PROFILE}" = "hybrid" ]; then
    echo "--- Warmup run (JIT, discarded) ---"
    set +e
    ${BENCH_CMD} > "${WARMUP_FILE}" 2>&1
    WARMUP_EXIT=$?
    set -e

    if [ ${WARMUP_EXIT} -ne 0 ] && ! grep -q "METRIC_JSON" "${WARMUP_FILE}"; then
        echo "WARMUP CRASHED (exit ${WARMUP_EXIT})"
        echo "--- Last 20 lines ---"
        tail -20 "${WARMUP_FILE}"
        exit 1
    fi
    echo "Warmup done."
    echo "--- Measured run (kept) ---"
else
    echo "--- Single run (profile: ${PROFILE}) ---"
fi

# ===========================================================================
# Measured run
# ===========================================================================

set +e
${BENCH_CMD} > "${RESULT_FILE}" 2>&1
BENCH_EXIT=$?
set -e

if [ ${BENCH_EXIT} -ne 0 ] && ! grep -q "METRIC_JSON" "${RESULT_FILE}"; then
    echo "BENCHMARK CRASHED (exit ${BENCH_EXIT})"
    echo "--- Last 20 lines ---"
    tail -20 "${RESULT_FILE}"
    exit 1
fi

# ===========================================================================
# Extract metrics
# ===========================================================================

METRICS=$(awk '/^METRIC_JSON$/{getline; print; exit}' "${RESULT_FILE}")
if [ -z "${METRICS}" ]; then
    echo "ERROR: No METRIC_JSON found in output"
    exit 2
fi

echo "${METRICS}" > "${METRICS_FILE}"
echo "Metrics: ${METRICS}"

# ===========================================================================
# Evaluate against baseline
# ===========================================================================

EVAL_EXIT=2
if [ -f "benchmark/evaluate.sh" ]; then
    echo "---"
    bash benchmark/evaluate.sh "${BASELINE}" "${RESULT_FILE}"
    EVAL_EXIT=$?
else
    echo "WARNING: No benchmark/evaluate.sh found. Manual evaluation required."
    echo "Baseline: ${BASELINE}"
    echo "Result:   ${METRICS_FILE}"
fi

# ===========================================================================
# Auto-append to experiments.tsv
# ===========================================================================

# Create TSV with header if it doesn't exist
if [ ! -f "${TSV_FILE}" ]; then
    mkdir -p benchmark
    printf "exp_id\ttimestamp\tparameter\told_value\tnew_value\tprimary_delta\ttime_delta\tmetric2\tmetric3\tmetric4\tverdict\tcommit_hash\truntime_profile\n" > "${TSV_FILE}"
fi

# Extract key metrics for TSV (best-effort, don't fail the whole run if parsing breaks)
TSV_TIMESTAMP=$(date -Iseconds 2>/dev/null || date)
TSV_PRIMARY_DELTA=""  # filled by agent or evaluate.sh
TSV_TIME_DELTA=""
# Extract up to 3 additional metrics from JSON (metric2, metric3, metric4)
# These are project-specific; the agent should fill them post-hoc if needed.
# The script attempts to extract common metric names as best-effort.
TSV_M2=""
TSV_M3=""
TSV_M4=""
for key in r2 accuracy f1_score mae; do
    TSV_M2=$(echo "${METRICS}" | sed -n "s/.*\"${key}\":[[:space:]]*\\([0-9.-]*\\).*/\\1/p" 2>/dev/null)
    [ -n "${TSV_M2}" ] && break
done
for key in n_peaks n_components n_clusters; do
    TSV_M3=$(echo "${METRICS}" | sed -n "s/.*\"${key}\":[[:space:]]*\\([0-9]*\\).*/\\1/p" 2>/dev/null)
    [ -n "${TSV_M3}" ] && break
done
for key in n_models n_iterations n_evals; do
    TSV_M4=$(echo "${METRICS}" | sed -n "s/.*\"${key}\":[[:space:]]*\\([0-9]*\\).*/\\1/p" 2>/dev/null)
    [ -n "${TSV_M4}" ] && break
done

case ${EVAL_EXIT} in
    0) TSV_VERDICT="KEEP" ;;
    1) TSV_VERDICT="DISCARD" ;;
    *) TSV_VERDICT="ERROR" ;;
esac

TSV_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "n/a")

# Append row (parameter/old/new/delta columns left for agent to fill)
printf "%s\t%s\t\t\t\t\t\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${EXP_ID}" "${TSV_TIMESTAMP}" "${TSV_M2}" "${TSV_M3}" "${TSV_M4}" \
    "${TSV_VERDICT}" "${TSV_COMMIT}" "${PROFILE}" >> "${TSV_FILE}"

echo "Logged to ${TSV_FILE}"

exit ${EVAL_EXIT}

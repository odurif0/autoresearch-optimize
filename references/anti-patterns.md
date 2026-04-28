# Anti-Patterns to Avoid in Autoresearch Optimization

These are generic patterns that typically fail or cause problems. Do not retry without strong justification.

## Measurement & Variance Anti-Patterns

1. **Comparing cold vs warm measurements**: If experiments use warmup runs but the baseline was measured cold (or vice versa), the time comparison is invalid. Always measure baseline and experiments with the same protocol.

2. **KEEPing on marginal improvements without confirmation**: If the primary metric delta is 2-3% (close to the threshold), a single run may be noise. Always do a confirmation run before KEEPing marginal results.

3. **Ignoring stochastic variance**: If the optimizer uses random seeds or evolutionary algorithms, a single run is unreliable. Use 3 runs with median, or at minimum 2 runs keeping the second.

4. **Measuring time on a loaded system**: Background processes, thermal throttling, or GC pauses can inflate time measurements. If time delta is the deciding factor, verify with a second run.

## Optimization Anti-Patterns

5. **Skipping Stage 2 (local refinement)**: If the optimization pipeline has a global stage followed by a local refinement stage, removing the local stage will almost always severely degrade quality. The global stage finds the basin, the local stage finds the optimum within it.

6. **Over-tightening constraints**: Making bounds/constraints stricter (e.g., reducing max parameter values by > 20%) often removes valid solutions. If a constraint change degrades quality, try relaxing instead.

7. **Over-relaxing constraints**: Conversely, allowing too much freedom (e.g., doubling max parameter values) can let the optimizer waste time in invalid regions. Change bounds incrementally (10-30%).

8. **Switching to a slower algorithm for marginal quality gain**: If algorithm A gives metric X in time T, and algorithm B gives metric X+1% in time 3T, the trade-off is rarely worth it. Prefer algorithms that maintain quality while improving speed.

9. **Replacing a working local optimizer**: If the local refinement stage uses a well-tested solver (e.g., Levenberg-Marquardt), replacing it with a different solver often fails because the new solver may not handle the problem structure (bounds, constraints, conditioning) as well.

10. **Micro-optimizations before algorithmic optimizations**: Compiler flags, `@fastmath`, `@inbounds`, loop unrolling -- these rarely improve the primary metric. Focus on algorithmic and parameter changes first.

11. **Batching multiple parameter changes**: Changing 2+ parameters simultaneously makes it impossible to attribute the effect. Keep one change per experiment, always.

## Process Anti-Patterns

12. **Not reverting on DISCARD**: If a DISCARDed change is left in the code, subsequent experiments are contaminated. Always verify `git diff` is clean after reverting.

13. **Modifying files outside the optimization scope**: Changing test files, GUI code, or configuration files unrelated to the optimization target. This creates noise in git history and may break unrelated functionality.

14. **Running `git checkout` on files modified by others**: If the working tree has uncommitted changes in files you didn't modify, `git checkout` will destroy them. Always check `git status` before reverting, and only revert files you actually changed.

15. **Declaring plateau too early**: 1 wave with 0 KEEP is not a plateau. Try at least 2 consecutive waves, then apply plateau recovery strategies before stopping.

## Benchmark Anti-Patterns

The benchmark is the foundation — if it's wrong, the entire loop is invalid.

16. **No fixed random seed**: The primary metric varies between identical runs. This makes every KEEP/DISCARD decision unreliable. Always seed the RNG in the benchmark, not just in the optimizer.

17. **Benchmarking the wrong function**: Wrapping `main()` which calls the optimizer indirection but not the actual optimization path. The benchmark must exercise the exact code path that will be modified.

18. **Primary metric too noisy**: If the metric varies by more than 1% between identical runs, the 2% KEEP threshold is meaningless. Increase benchmark duration, reduce external noise, or fix the optimizer's convergence.

19. **Generated benchmark not sanity-checked**: If the LLM generated the benchmark, running it once and trusting the result. Always run 3 times and verify the primary metric agrees within 0.5%.

20. **Hardcoding parameters in the benchmark**: If `benchmark.jl` sets `fwhm_max=1.0` directly, changing `src/core.jl` has no effect. The benchmark must import the parameter from the source file being optimized.

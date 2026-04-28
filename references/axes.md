# Exploration Axes

Generic dimensions to explore when planning optimization experiments. Not all axes apply to every project -- select the ones relevant to the current optimization target.

## High Leverage: Algorithm/Solver Changes

These typically have the largest impact on both quality and speed.

1. **Global optimizer algorithm**: If the project uses a global optimizer, try alternative algorithms. Common families:
   - Divide-and-conquer (DIRECT, DIRECT_L)
   - Evolutionary (ESCH, ISRES, differential evolution, CMA-ES)
   - Multi-start local (MLSL, MLSL_LDS)
   - Random sampling (CRS2_LM, random search)
   - Surrogate-based (Bayesian optimization)

2. **Local refinement algorithm**: If the pipeline has a Stage 2 local optimizer, alternatives include:
   - Levenberg-Marquardt (least-squares specific)
   - L-BFGS-B (bounded quasi-Newton)
   - Nelder-Mead (derivative-free)
   - Trust-region (TRF, dogleg)
   - Conjugate gradient

3. **Multi-start / restart strategy**: Run the optimizer multiple times from different starting points and keep the best result. Effective when the landscape is multi-modal.

## High Leverage: Constraint/Bounds Parameters

These control the search space geometry.

4. **Parameter upper bounds**: Widening max values (e.g., max size, max range) by 10-30% can allow the optimizer to find solutions it couldn't reach before. Too wide wastes evaluations.

5. **Parameter lower bounds**: Tightening min values can prevent degenerate solutions (e.g., zero-width components, zero-amplitude features). Loosening can allow smaller features.

6. **Coupled constraints**: Parameters that are linked (e.g., min spacing depends on max size via an angular constraint). Changing one affects the other -- explore the coupling parameter.

7. **Asymmetric constraints**: Allowing different bounds at boundaries/edges vs interior. Useful when boundary behavior differs from interior behavior.

## Medium Leverage: Hyperparameters

8. **Convergence tolerance**: Tighter tolerances (1e-12 vs 1e-8) may improve quality but cost time. Looser tolerances may speed up with minimal quality loss.

9. **Iteration limits**: Max iterations for global and local stages. Reducing can speed up without quality loss if the optimizer converges before hitting the limit.

10. **Time limits**: If the optimizer supports a time budget, reducing it forces faster convergence. Test whether quality is maintained.

11. **Population size** (for evolutionary algorithms): Larger populations explore more but take longer. Smaller populations are faster but may miss optima.

12. **Stopping criteria**: Patience-based stopping (stop after N iterations without improvement). More aggressive stopping saves time but may miss late improvements.

## Medium Leverage: Model Selection

13. **Competition threshold**: The minimum improvement required to prefer a more complex model over a simpler one. Lower values favor complexity, higher values favor simplicity.

14. **Minimum amplitude/significance**: The threshold for including a component in the model. Lower values detect smaller features but may overfit. Higher values are more conservative.

15. **Model complexity penalty**: The weight of the complexity penalty in the information criterion (BIC, AIC, etc.). Adjusting changes the bias-variance trade-off.

## Low Leverage: Micro-Optimizations

16. **Compiler flags / math modes**: `-O3`, `-ffast-math`, `@fastmath`, `@inbounds`. These rarely improve the primary metric and can degrade numerical stability.

17. **Memory layout / vectorization**: Row-major vs column-major, SIMD hints, loop tiling. Only relevant for compute-bound inner loops.

18. **Parallelism**: Threading, multiprocessing, GPU offloading. Effective if the benchmark has independent sub-problems.

## Failure-Driven Strategy

When planning experiments, use this priority order based on what previous waves revealed:

**If quality is the bottleneck** (primary metric far from theoretical optimum):
- Start with axes 1-3 (algorithmic changes)
- Then axes 4-7 (constraint changes)
- Then axes 13-15 (model selection)

**If speed is the bottleneck** (quality is good but time is too high):
- Start with axes 8-12 (hyperparameters)
- Then axes 1-3 (try faster algorithms)
- Then axes 16-18 (micro-optimizations)

**If both are stuck** (plateau on quality AND speed):
- Try axes 3 (multi-start) and 7 (asymmetric constraints) -- these break symmetry
- Try combining 2 parameters that were individually close to KEEP (plateau recovery)
- Try a fundamentally different approach (e.g., reformulate the objective function)

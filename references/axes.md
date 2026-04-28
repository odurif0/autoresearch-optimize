# Exploration Axes (Reference / Inspiration)

> **This document is a checklist of axis *categories*, not a prescriptive catalog.** Before planning any experiment, you MUST scan the actual project source code and build a project-specific axis list with concrete parameter names, current values, and proposed test values. Use this document only to verify you haven't overlooked a category of tunable parameters.

Generic dimension *types* to consider when exploring a codebase for optimization opportunities. Each section describes a category of parameters you might find in the source code, why they matter, and how to define concrete test values once you locate them.

## Methodological Innovations (Highest Leverage)

These change *what* is being optimized, not just *how fast*. They require understanding the problem domain, not just the code. Each axis describes a structural change to the approach itself — implement as a targeted code modification, not a numeric substitution.

### Objective Function Reformulation

A. **Add regularization**: L1 (sparsity), L2 (shrinkage), or elastic net penalty on model parameters. Reduces overfitting, especially with noisy data or many parameters.

B. **Switch information criterion**: BIC → AIC (lighter penalty, more complex models) or AICc (small-sample correction). Changes the bias-variance trade-off fundamentally.

C. **Add domain-specific penalty**: Physics constraints, smoothness penalties, monotonicity constraints. Encodes prior knowledge into the objective.

D. **Multi-objective formulation**: Optimize quality and speed simultaneously (Pareto front) instead of a single weighted metric.

### Model Structure Changes

E. **Add unmodeled phenomena**: If the model assumes symmetry but the data is asymmetric, add asymmetry parameters. If background is assumed constant, make it spatially varying.

F. **Change component/feature type**: Gaussian → Lorentzian/Voigt for spectroscopy, linear → spline for trends, fixed → adaptive basis functions.

G. **Hierarchical/multi-scale modeling**: Model coarse structure first, then fine details. Effective when features exist at multiple scales.

### Pipeline Architecture

H. **Coarse→fine optimization**: Grid search or random sampling to find promising regions, then local refinement on the top N candidates. Reduces risk of local minima.

I. **Preprocessing/filtering step**: Denoise, detrend, or normalize data before optimization. Can make the optimization landscape smoother.

J. **Sequential/iterative fitting**: Fit components one at a time, subtract, fit next (matching pursuit). Alternative to fitting all components simultaneously.

K. **Ensemble strategy**: Run multiple optimizers with different settings, keep the best result. Costs more time but more robust.

### Initialization & Seeding

L. **Data-driven initialization**: K-means++, PCA-informed, or peak-detection-based starting points instead of random. Better initial positions → faster convergence + better optima.

M. **Multi-start with pruning**: Run N short optimizations from different starts, keep only the top K for full refinement. Balances exploration vs cost.

### Heuristics & Adaptive Strategies

N. **Adaptive tolerance**: Start with loose tolerance, tighten as optimization progresses. Saves time in early iterations when far from optimum.

O. **Dynamic bounds narrowing**: After a coarse pass, narrow the search bounds around promising regions for the fine pass.

P. **Early stopping with validation**: Hold out a validation subset, stop when validation metric degrades (not just training convergence).

### Mathematical Reformulation

Q. **Change parameterization**: Log-space for positive parameters, logit-space for [0,1] bounds, relative coordinates instead of absolute. Can make the landscape more convex.

R. **Different decomposition**: SVD/PCA pre-processing, wavelet decomposition, Fourier basis instead of direct parameter fitting.

S. **Analytical gradient/Jacobian**: If the optimizer uses finite differences, providing an analytical gradient can dramatically improve speed and accuracy.

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

**First wave or resumed session**:
- ALWAYS start with 1-2 methodological experiments (axes A-S above, translated to project-specific proposals)
- Then fill the rest of the wave with HIGH-impact tuning experiments

**If quality is the bottleneck** (primary metric far from theoretical optimum):
- Start with methodological axes A-G (objective, model structure, pipeline)
- Then methodological axes L-M (initialization)
- Then HIGH axes (algorithm changes, constraint changes)
- Then MEDIUM axes related to model selection

**If speed is the bottleneck** (quality is good but time is too high):
- Start with methodological axes H-K (pipeline architecture, coarse→fine, ensemble)
- Then methodological axes N-P (heuristics, adaptive strategies)
- Then HIGH axes (try faster algorithms)
- Then MEDIUM axes (hyperparameters: tolerances, iteration limits)
- Then LOW axes (micro-optimizations) only as last resort

**If both are stuck** (plateau on quality AND speed):
- Try methodological axes A-D (reformulate objective) — this is the most powerful lever
- Try methodological axes Q-S (mathematical reformulation)
- Try multi-start strategies (methodological axis M)
- Try combining 2 parameters that were individually close to KEEP (plateau recovery)
- Try a fundamentally different approach: read recent papers, look for novel methods in the problem domain

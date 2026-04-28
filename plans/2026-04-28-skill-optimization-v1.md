# SKILL.md Optimization Plan — 9 Fixes

## Issues Found & Required Edits

After a full review of the 392-line SKILL.md after the methodological axes integration, 9 issues need fixing.

---

### Fix 1: Broken Numbering (Line 220)

**Location**: `SKILL.md:220`
**Current**: `7. **Detect runtime profile**` (follows `5.` on line 219 — line 6 is missing)
**Fix**: Change `7.` to `6.`
**Rationale**: Numbering skip from 5 to 7 — dead giveaway of a merge artifact.

---

### Fix 2: Phase 0 Step 4 — Broaden Source-Reading Instruction

**Location**: `SKILL.md:218`
**Current**:
```
4. Read the main source file to understand current parameter values.
```
**Fix**:
```
4. Read the main source file to understand current parameter values, algorithm choices,
   and structural assumptions (the same code you'll mine for methodological axes in step 8).
```
**Rationale**: Step 4 only mentions "parameter values" but step 8 asks the agent to also find structural assumptions. This ties the two together and avoids the agent reading the source twice with different mindsets.

---

### Fix 3: YAML Description — Mention Code/Method Optimization

**Location**: `SKILL.md:2-9`
**Current**:
```yaml
description: >
  Autonomous parameter/code optimization loop for any project with a benchmark
  ... optimize parameters, tune a model, run experiments ...
```
**Fix**:
```yaml
description: >
  Autonomous optimization loop for any project with a benchmark and evaluation
  script. Use when the user asks to run autoresearch, optimize parameters,
  improve code, tune a model, run experiments, or improve performance metrics
  (BIC, accuracy, latency, etc.) through systematic trial-and-error with
  automatic KEEP/DISCARD decisions. Supports both numeric hyperparameter tuning
  and methodological improvements (objective reformulation, pipeline
  restructuring, algorithmic changes). Also use when the user wants to resume a
  previous optimization session or plan a new wave of experiments.
```
**Rationale**: The description is what triggers the skill loading in Forge. It should mention methodological improvements so the skill is triggered even when the user asks about "improving the code" or "restructuring the pipeline", not just "tuning parameters".

---

### Fix 4: Critical Rules — Generalize "One Change"

**Location**: `SKILL.md:362`
**Current**:
```
- **One change per experiment.** Never batch multiple parameter changes
  (except during plateau recovery, strategy 3).
```
**Fix**:
```
- **One change per experiment.** Never batch multiple changes — whether parameter
  tuning, algorithm swap, or methodological restructuring (except during plateau
  recovery strategy 4).
```
**Rationale**: The rule now covers all change types (parameter, algorithm, methodological). Also corrected the plateau recovery strategy reference: strategy 3 became strategy 4 after adding the methodological reset as strategy 1.

---

### Fix 5: TSV Schema — Document Methodological Experiment Semantics

**Location**: `SKILL.md:350-352`
**Current**: Just the raw TSV header line, no explanation of how methodological experiments fill these columns.
**Fix**: Add after the header line:
```
For tuning experiments: `parameter` = parameter name, `old_value`/`new_value` = before/after values.
For methodological experiments: `parameter` = axis description (e.g., "add L2 regularization"),
`old_value`/`new_value` = "baseline"/"implemented".
```
**Rationale**: Without this, the agent logging a methodological experiment would be confused about what to put in `old_value`/`new_value` columns.

---

### Fix 6: TSV Analysis Commands — Fix Field References

**Location**: `SKILL.md:357-358`
**Current**:
```
- Pattern analysis: `cut -f4,11 experiments.tsv | sort | uniq -c`
- Failure analysis: `awk '$11=="DISCARD"' experiments.tsv | cut -f4 | sort | uniq -c`
```
**Fix**:
```
- Pattern analysis: `cut -f3,11 experiments.tsv | sort | uniq -c` shows which parameters/axes are most often KEPT
- Failure analysis: `awk '$11=="DISCARD"' experiments.tsv | cut -f3 | sort | uniq -c` shows which parameters/axes always fail
```
**Rationale**: Field 4 is `old_value` (a numeric value) — analyzing by `old_value` is meaningless. Field 3 is `parameter` (the parameter/axis name) — that's what you want to aggregate on. Using field 3 works for both tuning and methodological experiments.

---

### Fix 7: Resume Protocol — Add Axis Rebuild Step

**Location**: `SKILL.md:382-392`
**Current**: 7 steps, ends with "Plan and execute a new wave, prioritizing failure-driven insights."
**Fix**: Add step 7 (renumber existing 7 to 8):
```
7. **Rebuild the project-specific axis list** (Phase 0, Step 1, item 8): re-scan the source
   code for both tuning parameters and methodological opportunities. The code may have changed
   since the last session (KEPT experiments modified it). Cross-reference against the experiment
   history to remove already-tried combinations.
8. Plan and execute a new wave, prioritizing failure-driven insights and unexplored
   methodological axes.
```
**Rationale**: When resuming, the code may have changed from previous KEPTs. You can't just pick up the old axis list — you need to rebuild it. Also, the resume protocol was entirely missing the methodological axis concept.

---

### Fix 8: Make the "detect runtime profile" step number correct after fix 1

After fix 1, line 220 becomes step 6. But then step 8 becomes step 7 and step 9 becomes step 8. The numbering should flow: 1..6 for the original items, then 7 for axis building, then 8 for failure analysis.

Current after fix 1: 1,2,3,4,5,6 (runtime),8 (axes),9 (failure)
Should become: 1,2,3,4,5,6 (runtime),7 (axes),8 (failure)

So after fix 1, also change step `8.` to `7.` at line 221 and step `9.` to `8.` at line 266.

---

### Fix 9: Phase 1 Wave Composition — Add Plateau Recovery Strategy Number Check

**Location**: `SKILL.md:340`
**Current**: `strategy 4` (interaction exploration)
**Fix**: Verify this is correct after the methodological reset was added. The recovery strategies are now:
1. Methodological reset
2. Algorithmic reset
3. Constraint relaxation
4. Interaction exploration
5. Data-driven
6. Declare plateau

So "interaction exploration" is indeed strategy 4. Fix 4 above correctly references strategy 4.

---

## Summary

| # | Location | Issue | Impact |
|---|----------|-------|--------|
| 1 | `SKILL.md:220` | Numbering skip (5→7) | Confusing, looks broken |
| 2 | `SKILL.md:218` | Step 4 doesn't prime for methodological scan | Agent reads source twice with misaligned intent |
| 3 | `SKILL.md:2-9` | YAML description missing "methodological" | Skill won't trigger on code-improvement requests |
| 4 | `SKILL.md:362` | Critical rule only mentions "parameter changes" | Methodological changes undocumented in rules |
| 5 | `SKILL.md:350-352` | TSV schema undocumented for methodological experiments | Agent confused about column values |
| 6 | `SKILL.md:357-358` | TSV analysis uses wrong field (f4 instead of f3) | Analysis commands return meaningless results |
| 7 | `SKILL.md:382-392` | Resume protocol missing axis rebuild + methodological | Resume sessions work with stale axis list |
| 8 | `SKILL.md:221,266` | Renumber steps 8→7 and 9→8 after fix 1 | Consistent numbering |
| 9 | `SKILL.md:340` | Plateau recovery strategy number verification | Cross-reference Fix 4 — confirmed correct |

All fixes are low-risk, targeted text edits. No structural changes needed.

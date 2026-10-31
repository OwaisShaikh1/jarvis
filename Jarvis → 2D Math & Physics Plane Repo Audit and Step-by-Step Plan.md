# Jarvis → 2D Math & Physics Plane: Repo Audit and Step-by-Step Plan

*Based on a full read of github.com/OwaisShaikh1/jarvis (2 commits, head `2a22ed1`) and behaviour probes run in SBCL 2.2.9.*

## 1. What the repository actually contains

| File / module | Lines | What it does |
| --- | --- | --- |
| `jarvis.asd` | 48 | ASDF system; serial; Layers 1–5 real, 6–10 stubs |
| `src/knowledge/` | 59 + 329 | Layer 1: `fact`, `rule`, `principle` structs; hash-table DBs; predicate index |
| `src/inference/` | 40 + 318 | Layer 2: `unify`, `match-conditions`, agenda, `fire-rule`, `run-inference` |
| `src/truth-maintenance/` | 45 + 282 | Layer 3: justifications, cascade retraction, contradiction reporting |
| `src/trace/` | 52 + 262 | Layer 4: trace sessions, hook on `*on-rule-fired*` |
| `src/graph/` | 68 + 378 | Layer 5: derivation DAG (custom hash tables), subgraph, isomorphism |
| `src/abstraction`, `macro-formation`, `principle-optimizer`, `memory-pruning` | 3 each | Layers 6–9: `defpackage` only |
| `src/meta-controller/` | 12 | Layer 10: `defpackage` only |
| `main.lisp` | 1018 | Demo (`main`), CLI (`jarvis-cli`), persistence, why/prove explainers. Lives in `cl-user` |
| `data/facts.txt`, `data/rules.txt` | – | Persisted plist records (Socrates/Plato demo + a contradictory fact) |
| `.tmp-*.lisp`, `.tmp-output.txt` | – | Three ad-hoc scripts that print results (no assertions); output file is UTF-16 from PowerShell |
| `run.lisp`, `run-cli.lisp`, `load-system.lisp` | 25/17/18 | Entry scripts, each with a hard-coded `c:/Users/OWAIS/...` path |
| `architecture.md`, `setup steps.md`, `docs/cli-commands-report.md`, `README.md` | – | Design notes and CLI reference |

**Core data model (as implemented):**

- `fact`: `id predicate args negative-p derived-p usage-count last-accessed`. No slot for unit, value, status or uncertainty.
- `rule`: `id name conditions conclusion negative-p priority usage-count`. Conditions are a list of flat patterns `(pred arg …)`; the conclusion is one flat pattern.
- Variables are symbols starting with `?`; bindings are an alist.
- `justification`: `derived-id rule-id parent-ids`, one per derived fact, in `*justification-table*`, with a reverse `*dependents-table*`.
- Facts and rules are mutated only through `store-fact`, `retract-fact`, `store-rule` etc.; other layers hook in through `*on-rule-fired*` / `*on-cycle-end*`.

**Findings about dependencies:** `cl-graph`, `alexandria` and `cl-ppcre` are declared in `jarvis.asd` but never called anywhere (the graph layer builds its own hash-table graph). The eight core source files load in plain SBCL with no Quicklisp.

## 2. Verified behaviours that affect this project

I loaded Layers 1–4 in SBCL and probed them directly.

| # | Probe | Result | Why it matters for a numeric/physics plane |
| --- | --- | --- | --- |
| P1 | Fact `mass(b1, 2)` vs rule pattern `(mass ?b 2.0)` | **No match** | Matching uses `equal`; `2` ≠ `2.0`, and floats must be bit-identical. Numeric terms need tolerance-aware matching. |
| P2 | Rule conclusion `(speed ?b (/ ?d ?t))` with `dist=10`, `time=2` | Stored literally as `speed(b1, (/ ?D ?T))` | There is **no arithmetic**, and `apply-bindings` is flat, so variables inside nested lists are never substituted. |
| P3 | `p(a, nil)` and `q(a, z)` joined on `?y` | **Rule fired wrongly** | `unify` treats a variable bound to `NIL` as unbound. Also affects any value that is legitimately false/empty. |
| P4 | `mortal(a)` derivable from two rules; retract one parent | `mortal(a)` is removed even though `god(a)` still supports it | The TMS keeps **one** justification per fact and cascades unconditionally. For tuning parameters this will over-retract. |
| P5 | `run-inference` called without a trace session | **0 justifications created** | Justifications are only added by the CLI wrapper `run-inference-with-trace-and-tms` from trace steps. Any new code path that calls `run-inference` directly bypasses the TMS. |
| P6 | `infer` run twice | Second run reports the already-derived fact as "new", re-records a trace step and rewrites its justification | Re-inference after a parameter change will churn justifications and mis-report counts. |

From reading the code (not probed):

- `main.lisp` `parse-one-form` uses `read-from-string` with the default `*read-eval*` (T). A CLI line such as `add-fact #.(…)` evaluates code. The same applies to `read` in `load-persistent-state`. This must be closed **before** adding any expression evaluator.
- Persistence uses relative paths (`data/…`), so the CLI only works when started from the repo root. Persisted derived facts are reloaded **without** justifications, so `supported-p` is false for them and cascade retraction will not work on them.
- The agenda uses `sort` (unstable) on rule priority; ties fire in an unspecified order, so traces are not reproducible.
- Equality on fact arguments is open-coded with `equal` in six places (listed in step 2.1).

## 3. Design decisions to settle first (recommended defaults)

| ID | Decision | Recommended default |
| --- | --- | --- |
| D1 | Where the plane lives | New `src/plane/` modules loaded after Layer 5. Leave the Layer 6–10 stubs untouched. |
| D2 | How numbers appear in facts | Keep `fact-args` as a flat list. Allow numbers and a `quantity` struct (value + dimension). Replace all `equal` comparisons with one `term-equal` that is tolerance-aware for numbers. |
| D3 | Fact metadata | Add one `meta` plist slot to `fact` (`:status :unit :method :uncertainty :source`) instead of many slots. Serialize it in persistence. |
| D4 | Arithmetic in rules | Add two reserved condition forms evaluated after unification: `(:test <expr>)` and `(:is ?var <expr>)`. Expressions are evaluated by a **whitelisted** evaluator, never `eval`. |
| D5 | Tunable parameters | Model as retractable root facts with `status :tuned`. `set` = retract old value (cascade) + assert new + re-infer. |
| D6 | Numeric results | Stored as derived facts whose justification `rule-id` is a pseudo-rule (e.g. `NUM:RK4`) and whose `meta` records step, tolerance and error estimate. |
| D7 | Algebra engine | Write a small expression-tree engine in Lisp (no external CAS). Revisit only if Phase 5 scope grows. |
| D8 | Test framework | FiveAM (or Parachute). Add as a dev-only system `jarvis/tests`. |

## 4. Step-by-step plan

Each step names the file(s), the change, and a **Done when** check.

### Phase 0 — Baseline and hygiene

0.1 **Make paths portable.** In `load-system.lisp`, `run.lisp`, `run-cli.lisp` replace the hard-coded `c:/Users/OWAIS/...` with a path from `*load-truename*` (or `(asdf:initialize-source-registry ...)`). *Done when:* a fresh clone runs `sbcl --non-interactive --load run.lisp` with no edits.

0.2 **Remove unused dependencies.** Delete `cl-graph`, `alexandria`, `cl-ppcre` from `:depends-on` in `jarvis.asd` (or actually use them). Update the README and `setup steps.md`. *Done when:* the system loads without Quicklisp.

0.3 **Capture a golden baseline.** Run `demo` and the three `.tmp-*` scripts; save stdout as UTF-8 files under `tests/golden/`. Tag commit `baseline-v0.1`.

0.4 **Convert `.tmp-*` scripts into real tests.** Create `tests/` with a `jarvis/tests` ASDF system and port the three scripts into assertions (derived fact exists, contradiction detected, cascade retraction removes dependents). Delete the `.tmp-*` files and the UTF-16 `.tmp-output.txt`.

0.5 **Fix `read` safety.** In `parse-one-form` and `load-persistent-state` bind `*read-eval*` to `nil` and `*package*` to a fixed package. *Done when:* `add-fact #.(+ 1 2)` is rejected with a parse error (add as test).

0.6 **Make persistence location explicit.** Resolve `data/` relative to the system root (`asdf:system-relative-pathname`) so the CLI works from any directory.

0.7 **Split `main.lisp`.** Move CLI code into `src/cli/` (package `jarvis.cli`), persistence into `src/persistence/`, the demo into `examples/demo.lisp`. Keep `main` and `jarvis-cli` as exported entry points. *Done when:* golden transcripts from 0.3 still match.

### Phase 1 — Core engine bug fixes

1.1 **Fix NIL-bound variables (P3).** Change `lookup-binding` to return `(values value found-p)` (use `assoc` result, not `cdr`), and update `unify` and `apply-bindings` to use `found-p`. Add the P3 case as a regression test.

1.2 **Make `apply-bindings` recursive** so variables inside nested lists (e.g. `(f (g ?x))`) are substituted. Test with a nested conclusion.

1.3 **Make agenda ordering deterministic.** Use `stable-sort`, with rule-id as tiebreak. *Done when:* two runs produce identical traces.

1.4 **Stop re-reporting existing facts (P6).** In `fire-rule`/`run-inference`, detect when `store-fact` returned a pre-existing fact and: do not count it as new, and do not overwrite its justification (add it as an alternative, see 2.5).

1.5 **Route all inference through one function (P5).** Move the trace + TMS wiring from `run-inference-with-trace-and-tms` into a library function (e.g. `jarvis.truth-maintenance:run-inference-with-tms`) that the CLI and all new code use. Ideally the TMS installs its own listener on `*on-rule-fired*` so justifications are written at firing time.

1.6 **Rebuild justifications on load.** After `load-persistent-state`, either re-derive (clear derived facts, re-run inference) or store justifications in `facts.txt`. *Done when:* `retract` on a reloaded root cascades correctly.

### Phase 2 — Core extensions (required by the plane)

2.1 **Introduce `term-equal` and use it everywhere.** Replace `equal` on fact arguments in: `knowledge.lisp` `store-fact` and `fact-exists-p`; `inference.lisp` `unify` (bound-value check and ground-atom check); `trace.lisp` `inputs-from-bindings`; `main.lisp` `handle-add-fact-command` (the `already` check) and `register-opposite-polarity-contradictions`. `term-equal`: numbers compare by relative+absolute tolerance (configurable `*numeric-tolerance*`); `quantity` compares by dimension + converted value; everything else `equal`.

2.2 **Add fact metadata.** Add a `meta` plist slot to `fact` in `knowledge.lisp`; export `fact-meta`. Update `make-fact` (keyword `:meta`), `fact->record`/`record->fact` in persistence, `format-fact-with-id` in `tms.lisp`, `fact-label` in `graph.lisp`, and `print-fact-brief` in the CLI.

2.3 **Procedural attachment in conditions (D4).** In `match-conditions`, treat `(:test <expr>)` as a guard (evaluate with current bindings; fail if false) and `(:is ?v <expr>)` as a binding (evaluate, bind `?v`). Do this after the positive patterns to the left have bound their variables. Update `valid-pattern-p` / `valid-conditions-p` in the CLI so these forms are accepted.

2.4 **Whitelisted expression evaluator.** New file `src/plane/expr.lisp`: allowed operators `+ - * / expt sqrt sin cos tan atan2 exp log abs min max`, plus numeric literals, quantities and `?vars` already bound. Reject anything else. No `eval`, no symbol interning from input. Unit tests for rejects.

2.5 **Multi-justification TMS (P4).** Change `*justification-table*` to map `fact-id → list of justifications`. A derived fact stays believed while **at least one** justification has all parents believed. Rewrite `retract-with-support` / `collect-unsupported` accordingly (a fact is removed only when its last support disappears). Update `add-justification`, `justification-for` (return list), `dependency-parents`, `trace-roots-recursively`, `explain-why-*` and `explain-proof-forward` in the CLI. *Done when:* the P4 probe keeps `mortal(a)` after retracting `human(a)`.

2.6 **Assumption support.** Add `status :tuned` / `:given` root facts and an API `replace-assumption (old-fact-id new-args)` in the TMS that retracts the old value (with cascade) and asserts the new one atomically, returning the list of retracted and re-asserted ids for reporting.

2.7 **Incremental re-inference.** After `replace-assumption`, run inference only on rules whose conditions mention the changed predicate (use `*predicate-fact-index*`), then fall back to a full pass. *Done when:* a parameter change on a 1000-fact KB does not re-fire unrelated rules.

### Phase 3 — Units and dimensions

3.1 **`dimension` type.** Exponent vector over base dimensions (L, M, T, Θ, I; extend as needed). Functions: multiply, divide, power, equal-p, dimensionless-p.

3.2 **`quantity` type.** `(value dimension)` stored in SI. Parser from `"9.81 m/s^2"`, `"30 deg"`, `"2.5 kg"` into SI; printer back to the user's unit.

3.3 **Dimension-checked arithmetic.** Extend the evaluator from 2.4 to propagate dimensions: `+`/`-` require equal dimensions; `*`/`/`/`expt` combine them; `sin`/`cos` need dimensionless (angles in rad); `sqrt` halves exponents.

3.4 **Rule-time dimension check.** When `add-rule` is called, symbolically type-check `:test`/`:is` expressions against parameter dimensions declared in the plane schema. Reject inconsistent rules with a clear message.

3.5 **Tests:** `m/s * s = m`, reject `m + s`, `sqrt(m^2) = m`, deg/rad conversion.

### Phase 4 — 2D plane model (`src/plane/`)

4.1 **Package and ASDF module.** `src/plane/package.lisp`, listed after `src/graph` in `jarvis.asd`. Exports only what the CLI needs.

4.2 **Frames and transforms.** `frame` struct (name, origin, rotation, scale, parent) and functions to convert points/vectors between frames. A default `world` frame.

4.3 **Primitives as facts.** Encode `point`, `vector`, `line`, `segment`, `circle`, `polygon`, `curve` as predicates (`(point p1 world x y)`), with numeric args as `quantity` or plain numbers, so the existing KB, TMS and CLI handle them.

4.4 **Physical entities.** `particle`, `rigid-body` (mass, inertia, position, angle), `spring`, `incline`, `wall`, `field-region`. Each parameter is a fact `(param <entity> <name> <value>)` with `meta` `:status` in `{given, tuned, derived, inferred}` and `:bounds`.

4.5 **Plane schema.** A registry that declares for each entity type: parameter names, dimensions, default bounds. Used by 3.4 and by the CLI to list tunable parameters.

4.6 **Tests:** frame round-trip, distance between points, entity creation produces the expected facts and dimensions.

### Phase 5 — Symbolic algebra core

5.1 **Expression tree** (`src/plane/algebra.lisp`): numbers, symbols, `+ * expt` n-ary with canonical ordering, functions `sin cos exp log sqrt`.

5.2 **Simplify:** constant folding, identity elements, like-term collection, `x*x → x^2`.

5.3 **Substitute and differentiate** (all of 5.1's operators, chain rule).

5.4 **Solve for one unknown:** linear in the unknown, then quadratic, then bracketed numeric root as fallback (reuse Phase 7 solver).

5.5 **Derivations as justified facts.** Each symbolic result is asserted as a derived fact with a justification whose rule-id names the law used and whose parents are the premises. Store the expression in `meta :expr`.

5.6 **Tests:** derivative table, simplify round trips, solve `v² = u² + 2as` for each variable.

### Phase 6 — Laws as rules

Write each law as a normal Jarvis rule using the Phase 2 forms. Ship them in `data/laws/*.rules` (loaded on demand) with a test per law.

6.1 **Geometry:** distance, slope, angle between vectors, polygon area, line–circle intersection, tangency.

6.2 **Kinematics:** `v = u + at`, `s = ut + ½at²`, `v² = u² + 2as`, projectile (range, apex, time of flight), uniform circular motion.

6.3 **Dynamics:** `F = ma` per axis, friction on an incline, Hooke's law, work-energy, momentum conservation, torque and `τ = Iα`.

6.4 **Law registry:** each law has a name, a dimension signature, and the assumptions it carries (e.g. "no drag"). Assumptions become root facts so a contradiction (e.g. drag present) can retract them through the TMS.

### Phase 7 — Numeric layer

7.1 **RK4 integrator** for `dy/dt = f(t, y)` with fixed step; vector states for 2D.

7.2 **Adaptive RK45** (Dormand–Prince) with tolerance and step-size control.

7.3 **Event detection:** root-find on user-defined event functions (ground contact, apex, crossing) with sign-change bracketing and bisection/secant refinement.

7.4 **Algebraic solver:** Newton–Raphson with finite-difference Jacobian, damped steps, convergence report.

7.5 **Entering the KB:** each numeric result becomes a derived fact with `meta` `:method :step :tol :error-estimate`, justified by a pseudo-rule such as `NUM:RK45` with the input parameters as parents.

7.6 **Cross-checks:** projectile without drag must match the closed form from 6.2 within tolerance; add as tests.

### Phase 8 — Tune, sweep, derive, infer

8.1 **`set` / `unset`.** Wraps `replace-assumption` (2.6) + incremental inference (2.7); prints which facts were retracted, re-derived and changed value.

8.2 **`sweep`.** Vary one or two parameters over a range; for each point set, infer, read an output fact, collect into a table; restore the original value afterwards. Export CSV.

8.3 **`derive <query>`.** Try backward symbolic derivation first (the `*predicate-rule-index*` already exists for this and is unused), then numeric fallback. Always return the justification.

8.4 **`sensitivity`.** Symbolic derivative if the output expression is available, otherwise central finite difference.

8.5 **`infer-params` (inverse problem).** Inputs: observations (facts with uncertainty), unknown parameters with bounds. Steps: (a) try algebraic inversion via 5.4; (b) else Levenberg–Marquardt on residuals using the Phase 7 simulation; (c) output estimate, residuals, covariance approximation, and **identifiability warnings** (near-singular Jacobian).

8.6 **Contradiction reporting.** When observations conflict with the model, use the existing `check-contradictions` machinery and, with 2.5 in place, report the minimal set of root assumptions involved instead of forcing a fit.

8.7 **Record results as inferred facts** (`status :inferred`) with their uncertainty so later queries can reuse them and `why` can explain them.

### Phase 9 — Explainability

9.1 **Extend the graph layer.** In `graph.lisp` add node types `:quantity` and `:numeric-step` and edge relation `:solved-from` alongside `:fact`, `:rule`, `:input-of`, `:produces`. Update `package.lisp` docs and `isomorphic-p` signatures.

9.2 **Extend the trace layer.** Allow trace steps whose `rule-id` is a pseudo-rule (`NUM:*`, `SYM:*`) and carry `meta`. Update `trace->graph` labels via `rule-label`.

9.3 **Update CLI explainers.** `why`, `why -r`, `prove`: show units, status, method and error estimate for each line. Show "inferred from observations O1, O2 with residual R".

9.4 **`model-card` command.** Lists entities, parameters (value, unit, status, bounds), active laws, assumptions and unresolved unknowns.

### Phase 10 — CLI additions (in `src/cli/`)

10.1 Commands: `plane-new`, `add-entity`, `set`, `unset`, `show-model`, `derive`, `simulate`, `sweep`, `infer-params`, `sensitivity`, `explain`, `export`, `plane-reset`.

10.2 Keep existing commands and fact-id forms (`FACT-1`, `fact1`, `fact#1`, `1`) unchanged.

10.3 Parse units in command arguments (`set b1.mass 2.5 kg`) through 3.2, with `*read-eval*` off.

10.4 Update `help` and `docs/cli-commands-report.md`.

### Phase 11 — Visualization and export

11.1 **SVG writer** (`src/plane/svg.lisp`): axes, entities, force/velocity vectors, trajectories, annotated derived values. Output to a file; no GUI dependency.

11.2 **ASCII fallback** for terminal use.

11.3 **CSV/JSON export** of trajectories, sweeps and parameter tables.

### Phase 12 — Tests, docs, release

12.1 **Acceptance scenarios (each a test):**

1. Projectile: set `v0`, angle; derive range/apex/time symbolically; add linear drag and compare numeric result with the closed form.
2. Block on a friction incline: tune angle and μ, derive acceleration; infer μ from an observed slide time.
3. Spring–mass: derive period; infer `k` from noisy positions and warn that only `k/m` is identifiable if `m` is free.
4. Geometry: circle–line tangency from partial constraints.
5. Contradiction: two incompatible observations produce a minimal conflicting-assumption report.

12.2 **Regression:** the Phase 0 golden transcripts still pass.

12.3 **Docs:** update `README.md` (layers, plane, run instructions), `architecture.md` (new layer and data flow), and `docs/cli-commands-report.md`.

12.4 **Tag** `v0.2.0`.

## 5. File-level change map

| File | Changes |
| --- | --- |
| `jarvis.asd` | Drop unused deps; add `src/plane`, `src/cli`, `src/persistence`; add `jarvis/tests` system |
| `src/knowledge/knowledge.lisp` | `term-equal`; fact `meta` slot; use `term-equal` in `store-fact`, `fact-exists-p` |
| `src/inference/inference.lisp` | `lookup-binding` found-p; recursive `apply-bindings`; `:test`/`:is` in `match-conditions`; stable agenda; no re-report of existing facts |
| `src/truth-maintenance/tms.lisp` | Multi-justification; `replace-assumption`; integrated `run-inference-with-tms`; update proof/root tracing |
| `src/trace/trace.lisp` | `term-equal` in `inputs-from-bindings`; pseudo-rule steps; step `meta` |
| `src/graph/graph.lisp` | New node/edge types; labels with units and method |
| `main.lisp` | Split into `src/cli`, `src/persistence`, `examples/demo.lisp`; `*read-eval*` off; serialize `meta`; new commands |
| `load-system.lisp`, `run.lisp`, `run-cli.lisp` | Portable paths |
| New `src/plane/*` | `expr`, `units`, `frames`, `entities`, `algebra`, `laws`, `ode`, `solve`, `infer`, `svg`, `export` |
| New `tests/*` | FiveAM suites and golden transcripts |
| New `data/laws/*` | Geometry, kinematics, dynamics rule files |

## 6. Order and dependencies

Phase 0 and Phase 1 must finish before anything else. Phase 2 blocks Phases 3–8 (numbers, metadata, arithmetic, multi-support TMS). Phases 3 and 4 can proceed in parallel after Phase 2. Phase 5 and Phase 7 are independent of each other; Phase 6 needs 3, 4 and 5; Phase 8 needs 2, 5, 6 and 7; Phases 9–11 can start once Phase 8's APIs are stable.

## 7. Open questions for the project owner

1. Should the plane be a separate system (`jarvis-plane`) or part of `jarvis`? (Default above: same system, new module.)
2. Is a tolerance-based numeric match acceptable inside the logic layer, or must exact symbolic matching be kept and numbers handled only in guards?
3. Is a self-written algebra engine acceptable, or should an existing CAS (e.g. via Maxima) be allowed as an optional backend?
4. Do you want Layers 6–10 (abstraction, macros, principles, pruning, meta-controller) to learn from plane derivations later? If yes, the Phase 9 trace extensions should be designed with that in mind.

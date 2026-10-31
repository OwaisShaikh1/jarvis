# Jarvis User Guide

Jarvis is a symbolic reasoning engine written in Common Lisp. It stores facts
and rules, derives new facts by forward chaining, records provenance, and
retracts unsupported conclusions through its truth-maintenance system.

This guide covers the currently implemented runtime, CLI, persistence, and
inference features. The abstraction, macro, optimizer, pruning, and
meta-controller layers are scaffolded but are not yet implemented.

The separate `jarvis-plane` system now also provides units, coordinate frames,
native algebra, numerical integration/solvers, registered simulation models,
and executable physics-law formulas.

## Requirements

- [SBCL](https://www.sbcl.org/)
- ASDF, included with SBCL
- Quicklisp and FiveAM are optional and only needed for the test suite

All commands below are run from the repository root.

## Start Jarvis

Run the complete five-layer demonstration:

```text
sbcl --non-interactive --load "run.lisp"
```

Start the interactive CLI:

```text
sbcl --load "run-cli.lisp"
```

The CLI bootstrap loads the system, runs the demonstration once, and then
opens the `jarvis>` prompt. For development, load only the system:

```text
sbcl --load "load-system.lisp"
```

Then use `(main)` for the demonstration or `(jarvis-cli)` for the CLI.

## The Demonstration Pipeline

The built-in demo exercises the implemented Layers 1–5:

1. Reset the knowledge base, truth-maintenance tables, and trace archive.
2. Assert `human(socrates)` and `human(plato)`.
3. Add two rules:

   ```text
   human(?x)      -> mortal(?x)
   mortal(?x)     -> finite-life(?x)
   ```

4. Derive four facts through forward chaining.
5. Record a trace session with four steps and maximum depth two.
6. Store rule justifications for every derived fact.
7. Build and print a derivation graph.
8. Retract `human(socrates)` and cascade the retraction through its
   descendants.

Representative output:

```text
[inference] Derived 4 new fact(s):
  FACT-8  (FINITE-LIFE  PLATO)  derived=T
  FACT-7  (FINITE-LIFE  SOCRATES)  derived=T
  FACT-6  (MORTAL  PLATO)  derived=T
  FACT-5  (MORTAL  SOCRATES)  derived=T
[trace] Session SESSION-1 closed. 4 steps, max depth 2.
[TMS] Facts after  retraction: 3
```

After retraction, Plato and its conclusions remain while Socrates and its
dependent conclusions are removed.

## Interactive CLI Walkthrough

At the `jarvis>` prompt, the following commands demonstrate the complete
interactive workflow:

```text
help
reset

add-fact (human ada)
add-fact (curious ada)
add-rule human-implies-mortal ((human ?x)) (mortal ?x)
add-rule mortal-implies-finite ((mortal ?x)) (finite-life ?x)

facts
rules
infer
status

why FACT-4
why FACT-4 --recursive
prove FACT-4

retract FACT-1
facts
status
quit
```

Fact IDs may be written as `FACT-1`, `fact1`, `fact#1`, or `1`. IDs printed by
your session may differ because IDs remain unique within an SBCL process.

### CLI commands

| Command | Purpose |
| --- | --- |
| `help`, `commands` | Show available commands and ID syntax |
| `demo` | Run the complete Layers 1–5 demonstration |
| `status` | Show fact, rule, and trace counts |
| `add-fact (predicate args...)` | Assert a fact |
| `add-rule name ((conditions)) (conclusion)` | Add a production rule |
| `facts` | List stored facts and derived flags |
| `rules` | List stored rules |
| `infer [max-cycles]` | Run inference and record a trace |
| `why FACT-ID` | Show immediate support |
| `why FACT-ID --recursive` | Show the complete support tree |
| `why FACT-ID --proof` | Show a root-to-goal proof |
| `prove FACT-ID` | Alias for proof output |
| `retract FACT-ID` | Retract a fact and unsupported descendants |
| `reset` | Clear facts, rules, TMS state, and traces |
| `quit`, `exit` | Leave the CLI |

## Negative Facts and Rules

Negative conclusions are supported using either form:

```text
add-fact (!dead plato)
add-rule alive-implies-not-dead ((alive ?x)) (! dead ?x)
```

The rule derives a negative fact such as `!dead(plato)`. Negation is currently
fact-level; it does not yet define universal predicate disjointness.

## Explanations, Proofs, and Retraction

Suppose the following facts and rule are present:

```text
human(ada)
human(?x) -> mortal(?x)
```

After `infer`, `why` reports the direct justification:

```text
why FACT-3
```

Recursive explanation follows all parent facts back to root assumptions:

```text
why FACT-3 --recursive
```

Proof mode prints roots first and the requested conclusion last:

```text
prove FACT-3
```

Retraction uses the same dependency graph. Retracting `human(ada)` also
removes `mortal(ada)` and any later facts that depend on it.

## Common Lisp API

The public API can be used without the interactive CLI:

```lisp
(jarvis.knowledge:clear-databases)
(jarvis.truth-maintenance:clear-tms)
(jarvis.trace:clear-traces)

(jarvis.knowledge:store-fact
 (jarvis.knowledge:make-fact 'human 'ada))

(jarvis.knowledge:store-rule
 (jarvis.knowledge:make-rule
  'human-implies-mortal
  '((human ?x))
  '(mortal ?x)))

(multiple-value-bind (new-facts trace)
    (jarvis.engine:infer :quiet t)
  (format t "Derived: ~A~%" (length new-facts))
  (format t "Trace steps: ~A~%"
          (jarvis.trace:reasoning-trace-step-count trace)))
```

`jarvis.engine:infer` is the centralized path that combines inference,
trace recording, and truth-maintenance justifications. It accepts `:goal`,
`:max-cycles`, `:rules`, and `:quiet` keyword arguments.

## Plane Numerical and Physics API

Load the plane system from the repository root:

```lisp
(load "load-system.lisp")
(load "plane/jarvis-plane.asd")
(asdf:load-system :jarvis-plane)
```

Numerical methods include `jarvis.plane.numerics:rk4`,
`rk45`, `newton-solve`, and `levenberg-marquardt`. The simulation registry
ships `:ballistic`, `:spring-1d`, and `:incline-slide` models:

```lisp
(jarvis.plane.sim:simulate 'ball :ballistic 2d0)
```

Physics laws can be evaluated from a keyword-value property list and enabled
for batch evaluation:

```lisp
(jarvis.plane.laws:evaluate-law
 'jarvis.plane.laws::spring-period '(:mass 2d0 :k 50d0))
;; => approximately 1.2566370614

(jarvis.plane.laws:enable-law 'jarvis.plane.laws::projectile-range)
(jarvis.plane.laws:apply-enabled-laws
 '(:v0 10d0 :angle 0.7853981634d0 :g 9.81d0))
```

The plane CLI commands and full fact-backed law inference remain planned work.

## Matching and Unification

Rule variables are symbols beginning with `?`:

```lisp
((likes ?person logic))
```

Bindings are applied recursively, including nested list expressions:

```lisp
(speed ?body (/ ?distance 2))
```

The matcher supports:

- Ground conditions such as `(alive plato)`
- Repeated variables across conditions
- Variables bound to `NIL`
- Recursive conclusion substitution
- Range-restricted rules: every conclusion variable must occur in a condition
- Deterministic fact, rule, and agenda ordering
- Duplicate derivation suppression

Invalid range-restricted rules signal `jarvis.knowledge:rule-error` instead of
silently creating an unbound conclusion.

## Custom Numeric Matching

The knowledge layer provides an optional term-comparison hook. A hook returns
`:equal`, `:unequal`, or `NIL` for no opinion. The match context contains the
predicate, zero-based argument position, and original pattern:

```lisp
(let ((jarvis.knowledge:*term-equal-hook*
        (lambda (left right)
          (if (and (numberp left) (numberp right))
              (if (< (abs (- left right)) 0.01)
                  :equal
                  :unequal)
              nil))))
  (jarvis.inference:run-inference))
```

This allows a rule containing `2.0` to match a fact containing `2` without
changing the default exact fact-deduplication behavior. The optional
`*dedup-uses-policy*` switch enables policy-based deduplication when that is
explicitly desired.

## Persistence

The CLI stores state in the repository-relative `data/` directory:

```text
data/facts.txt
data/rules.txt
```

State is loaded once when the CLI starts and saved after `add-fact`,
`add-rule`, `infer`, `retract`, and `reset`. Persisted input is read with
reader evaluation disabled. On load, root facts and rules are restored,
derived facts are rebuilt through inference, and their justifications are
recreated.

## Contradiction Handling

Contradictory fact IDs can be registered through the truth-maintenance API:

```lisp
(jarvis.truth-maintenance:register-contradiction
 fact-id-a
 fact-id-b)

(jarvis.truth-maintenance:check-contradictions)
```

The TMS can trace each conflicting fact back to root assumptions and print
resolution options. Retraction of a suggested root fact then removes its
unsupported derivation chain.

## Tests and Validation

If Quicklisp and FiveAM are available:

```text
sbcl --non-interactive --load "tests/run-tests.lisp"
```

The repository also contains golden transcripts under `tests/golden/` for the
demo, negative reasoning, contradiction handling, and root-cause output.

## Current Scope

Implemented:

- Portable ASDF-relative entry points
- Knowledge representation and indexed fact/rule storage
- Positive and negative facts
- Forward-chaining inference and unification
- Recursive bindings and range restriction
- Deterministic ordering and duplicate suppression
- Configurable term-comparison hooks
- Centralized inference, tracing, and TMS integration
- Justification-based cascade retraction
- Contradiction registration and root-cause reporting
- Persistence with derived-state rebuild
- Interactive CLI explanations and proofs
- Derivation trace and graph output

Implemented plane foundation:

- Separate `jarvis-plane` ASDF system
- Numeric matching policies and term-equality hook installation
- SI unit parsing and five-component dimensions
- Whitelisted expression evaluation and dimensional analysis
- Coordinate frames with world/local transforms
- Plane primitives, entity registry, parameter kinds, and bounds
- Native symbolic algebra: canonicalization, substitution, differentiation, and
  linear/quadratic solving

Not yet implemented:

- Multiple justifications per derived fact
- Assumption contexts
- Procedural `:test` and `:is` conditions
- Full restricted-inference policy surface
- Derivation event records
- Scratch knowledge bases
- Maxima and cross-check algebra backends
- RK4/RK45, Newton, and Levenberg–Marquardt numerics
- Projectile, spring, and incline simulation/laws
- Abstraction, macro formation, principle optimization, memory pruning, and
  meta-controller layers

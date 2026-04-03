# Jarvis CLI Command Report

This report describes the terminal command interface implemented for Jarvis after system activation.

## Activation

Use one of the following startup flows from the project root:

1. Interactive CLI bootstrap (recommended):
   - `sbcl --load "run-cli.lisp"`
   - Loads the system, runs the demo once, then starts the CLI prompt.

2. Manual activation in REPL:
   - `sbcl --load "load-system.lisp"`
   - `(load "main.lisp")`
   - Optional state setup: `(main)`
   - Start CLI: `(jarvis-cli)`

## Command Syntax and Behavior

### help | commands
- Syntax: `help`
- Syntax: `commands`
- Behavior: Prints all available CLI commands and accepted fact-id formats.

### demo
- Syntax: `demo`
- Behavior: Executes the full layer 1-5 demonstration pipeline from a clean reset.

### status
- Syntax: `status`
- Behavior: Prints counts for current facts, rules, and completed traces.

### add-fact (predicate args...)
- Syntax: `add-fact (human plato)`
- Syntax: `add-fact (likes plato wisdom)`
- Syntax: `add-fact (!mortal harsh)`
- Syntax: `add-fact (! mortal harsh)`
- Behavior: Asserts one fact into the KB using a Lisp-style pattern.
- Notes: If the same fact already exists, the command reports the existing fact ID instead of duplicating it.
- Notes: Negative fact syntax is supported and stored as a negative fact (for example `!MORTAL(HARSH)`).

### add-rule <name> ((conditions)) (conclusion)
- Syntax: `add-rule human-implies-mortal ((human ?x)) (mortal ?x)`
- Syntax: `add-rule mortal-implies-finite-life ((mortal ?x)) (finite-life ?x)`
- Behavior: Adds one production rule to the rule DB using Lisp-style condition/conclusion patterns.
- Notes: Conditions must be a list of patterns; conclusion must be a single pattern.

### Negative rules
- Syntax: `add-rule alive-implies-not-dead ((alive ?x)) (! dead ?x)`
- Syntax: `add-rule alive-implies-not-dead ((alive ?x)) (!dead ?x)`
- Behavior: A negated conclusion is stored as a negative fact when the rule fires.
- Output example: if `alive(plato)` exists, inference can derive `!dead(plato)`.
- Notes: Negative rules still use normal positive conditions; only the conclusion is marked negative.
- Notes: The wrapped form `(! dead ?x)` is the canonical spelling.

### Set exclusion / disjointness (alive excludes dead)
- Current negation support is fact-level: negative rules derive negative facts such as `!dead(plato)`.
- If you want universal exclusion for all `x`, that is still a separate predicate-level disjointness feature.

### facts
- Syntax: `facts`
- Behavior: Lists all currently believed facts with IDs and derived flags.

### rules
- Syntax: `rules`
- Behavior: Lists loaded rules, their conditions, conclusions, and priorities.

### infer [max-cycles]
- Syntax: `infer`
- Syntax: `infer 500`
- Behavior: Runs inference, records a trace session, and updates TMS justifications from recorded trace steps.

### why <fact-id>
- Syntax: `why fact1`
- Syntax: `why FACT-1`
- Behavior: Returns immediate justification only (rule used and direct parent facts).
- If the fact is a root assumption, reports that it has no recorded derivation parents.

### why <fact-id> -p
- Syntax: `why fact1 -p`
- Syntax: `why fact1 --proof`
- Behavior: Prints a forward, mathematical-style proof from root assumptions to the target fact.
- Output format uses numbered lines with explicit rule references and parent line dependencies.

### wy <fact-id> -r
- Syntax: `wy fact1 -r`
- Syntax: `why fact1 -r`
- Syntax: `why fact1 --recursive`
- Behavior: Recursively prints the full support tree back to first causes (root assumptions).
- Presentation: Beautified tree layout with clear because/assumption markers.

### prove <fact-id>
- Syntax: `prove fact1`
- Syntax: `proof fact1`
- Behavior: Alias command for the same root-to-goal mathematical proof renderer.

### retract <fact-id>
- Syntax: `retract fact1`
- Behavior: Retracts the target fact and all transitively dependent facts via TMS support propagation.

### reset
- Syntax: `reset`
- Behavior: Clears the knowledge database, truth-maintenance state, and trace archive.

### quit | exit
- Syntax: `quit`
- Syntax: `exit`
- Behavior: Leaves the Jarvis CLI loop.

## Persistence

- Jarvis now persists facts and rules to separate text files in `data/`.
- Facts file: `data/facts.txt`
- Rules file: `data/rules.txt`
- Load behavior: CLI startup loads persisted facts/rules once per process.
- Save behavior: state is saved automatically after `add-fact`, `add-rule`, `infer`, `retract`, and `reset`.

## Fact ID Parsing

The CLI accepts these forms and normalizes them to internal fact IDs:

- `FACT-1`
- `fact1`
- `fact#1`
- `1`

## Notes on Reasoning Commands

- `why` gives one-hop explanation (immediate parent facts only).
- `why ... -r` or `wy ... -r` gives complete ancestry chain to roots.
- `why ... -p` or `prove ...` gives forward proof ordering (roots first, target last).
- Recursive output is cycle-safe via visited-node tracking.

## Contradiction Handling

When contradictory facts are both present during `infer`, the system behaves as follows:

### Detection and Root-Cause Analysis
- The TMS traces each contradictory fact **backward** through the justification graph to its root assumptions (original user-asserted facts).
- Each derivation chain is printed in a proof-like format, showing how the contradiction actually originated.

### Output Format
The output includes:
1. **Derivation proofs** for each contradictory fact, showing the chain from root assumptions to the conflict:
   ```
   [proof] How MORTAL(HARSH) was derived:
   [proof]   1. HUMAN(HARSH)  [root assumption]
   [proof]   2. MORTAL(HARSH) [from rule: human-implies-mortal]
   ```

2. **Two resolution options** listing the root facts to retract (one option to break each derivation chain):
   ```
   [TMS] Root causes to resolve:
   
   [TMS] Option 1 — Retract root fact(s) that caused MORTAL(HARSH):
   [TMS]   - retract HUMAN(HARSH)
   
   [TMS] Option 2 — Retract root fact(s) that caused !MORTAL(HARSH):
   [TMS]   - retract FACT-10
   ```

### Resolution
- Choose one option by retracting the suggested root fact(s): `retract <fact-id>`
- Retracting a root fact automatically cascades the retraction through all derived facts, eliminating the contradiction source.
- If you retry `infer` after resolving, the contradiction will no longer re-occur (assuming the root cause is not re-derived).

## Inference Loop Fix Included

The inference engine was updated to stop when a cycle fires zero new rule instantiations.
This prevents unnecessary spinning after convergence and avoids hitting max-cycles during stable states.

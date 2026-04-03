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

## Inference Loop Fix Included

The inference engine was updated to stop when a cycle fires zero new rule instantiations.
This prevents unnecessary spinning after convergence and avoids hitting max-cycles during stable states.

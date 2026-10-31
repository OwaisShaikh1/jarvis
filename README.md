# Jarvis

Jarvis is a symbolic AI reasoning system written in Common Lisp.

It is designed as a layered architecture that starts with explicit knowledge and rules, performs forward-chaining inference, maintains logical consistency with truth maintenance, records reasoning traces, and represents reasoning as graphs for future abstraction and optimization.

## What The System Is

Jarvis is a research-oriented reasoning engine with a command-line interface.

It combines:
- A structured knowledge base of facts and rules
- A forward-chaining inference engine
- A JTMS-style truth maintenance layer for dependency-aware retraction
- A trace recorder for explainability
- A graph layer for derivation structure

The architecture is intended to grow into higher-level abstraction, macro formation, principle optimization, memory pruning, and a meta-controller.

## What It Does

Current implemented core (Layers 1 to 5):
- Stores asserted and derived facts
- Stores rules and fires them through pattern matching and unification
- Derives new facts until convergence or cycle limit
- Records justifications so derived facts can be retracted with dependency propagation
- Captures trace sessions and builds derivation graphs
- Provides CLI commands for inspection, inference, explanation, proof output, retraction, reset, and dynamic fact/rule insertion

Planned/placeholder layers (currently package stubs):
- Abstraction engine
- Macro formation
- Principle optimizer
- Memory pruning
- Meta-controller

## Why It Is Useful

Jarvis is useful when you need:
- Transparent reasoning instead of opaque model behavior
- Auditable chains of inference and provenance
- Explicit control over rules and knowledge updates
- Dependency-aware retraction and consistency handling
- A foundation for experimenting with symbolic abstraction and cognitive-architecture-inspired workflows

This makes it strong for:
- Educational AI and logic-system learning
- Explainable symbolic reasoning prototypes
- Rule-engine experimentation
- Research into abstraction and principle formation over traces

## What It Uses

Language/runtime:
- Common Lisp
- SBCL

Build/system manager:
- ASDF
- Quicklisp (optional; only required for the FiveAM test suite)

Runtime dependencies:
- None beyond SBCL and ASDF

Test dependency:
- FiveAM via Quicklisp

Project entry files:
- [jarvis.asd](jarvis.asd)
- [load-system.lisp](load-system.lisp)
- [main.lisp](main.lisp)
- [run.lisp](run.lisp)
- [run-cli.lisp](run-cli.lisp)

Reference docs included in repo:
- [architecture.md](architecture.md)
- [setup steps.md](setup%20steps.md)
- [docs/cli-commands-report.md](docs/cli-commands-report.md)

## How It Works

### High-Level Flow

1. Knowledge layer stores facts/rules in indexed databases.
2. Inference engine matches rule conditions against facts and fires rules.
3. Newly derived facts are inserted with derived metadata.
4. Trace layer records each rule firing step and session metrics.
5. TMS records justifications (derived fact <- rule <- parent facts).
6. Graph layer converts traces into derivation DAG structures.
7. CLI lets you inspect and drive the cycle interactively.

### Runtime Cycle

Problem input -> inference -> TMS update -> trace capture -> graph representation.

Long-term intended cycle adds:
trace mining -> abstraction -> macro/principle optimization -> pruning -> controller decisions.

### Explanation Modes

The CLI supports multiple explanation styles:
- Immediate why: one-hop parent support
- Recursive why: full ancestry/support chain
- Proof mode: root-to-goal, line-based proof output

## CLI Quick Reference

Main commands:
- help, commands
- demo
- status
- add-fact
- add-rule
- facts
- rules
- infer [max-cycles]
- why / wy
- prove
- retract
- reset
- quit, exit

Fact ID forms accepted:
- FACT-1
- fact1
- fact#1
- 1

See full command behavior in [docs/cli-commands-report.md](docs/cli-commands-report.md).

## Setup From GitHub

### 1. Prerequisites

Install:
- SBCL: https://www.sbcl.org

### 2. Clone

```bash
git clone <your-repo-url>
cd jarvis
```

### 3. Optional: install test dependencies

Quicklisp is only needed to run the FiveAM tests. If Quicklisp is installed, load
FiveAM in SBCL with:

```lisp
(ql:quickload :fiveam)
```

### 4. Configure project path for ASDF

The entry scripts register the project relative to their own location, so no
machine-specific path update is required.

### 5. Run options

Interactive development load:

```bash
sbcl --load "load-system.lisp"
```

One-shot demo run:

```bash
sbcl --non-interactive --load "run.lisp"
```

Interactive CLI run:

```bash
sbcl --load "run-cli.lisp"
```

## Project Status

Implemented:
- Layer 1 Knowledge representation
- Layer 2 Inference
- Layer 3 Truth maintenance
- Layer 4 Trace recording
- Layer 5 Graph representation

Scaffolded stubs:
- Layers 6 to 10

## Suggested Next Steps

1. Make ASDF path setup portable so clone-and-run is zero-edit.
2. Add automated tests for CLI command flows and explanation/proof output.
3. Implement first abstraction pass over trace graphs.
4. Add benchmark scenarios for inference depth and convergence behavior.

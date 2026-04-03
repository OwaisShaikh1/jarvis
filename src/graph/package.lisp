;;; Layer 5 — Graph Representation
;;;
;;; Converts a TRACE (from Layer 4) into a directed acyclic graph (DAG)
;;; that the Abstraction Engine can structurally compare and mine.
;;;
;;; Node types:
;;;   :fact   — a ground fact that was believed during the trace.
;;;   :rule   — a rule that fired, connecting input facts to an output fact.
;;;
;;; Edge semantics:
;;;   fact  ──[input-of]──▶  rule   — this fact satisfied one condition.
;;;   rule  ──[produces]──▶  fact   — this rule derived/asserted the fact.
;;;
;;; The graph is built on top of the cl-graph library (adjacency-list backend).
;;; Each DERIVATION-GRAPH wraps a cl-graph:graph together with a label index
;;; so callers can look up nodes by fact-id or rule-id without walking the
;;; whole adjacency list.
;;;
;;; Key operations exposed:
;;;   trace→graph   — convert a stored trace into a derivation graph.
;;;   subgraph      — extract the subgraph reachable from a given node.
;;;   graph-depth   — longest path from any root node.
;;;   isomorphic-p  — structural equality test used by the Abstraction Engine.

(defpackage :jarvis.graph
  (:use :cl :jarvis.trace)
  (:export
   ;; ── Derivation-graph structure ────────────────────────────────────────────
   #:make-derivation-graph  ; (trace) → derivation-graph
   #:derivation-graph-id    ; dg → symbol  (same as trace session-id)
   #:derivation-graph-raw   ; dg → underlying cl-graph object

   ;; ── Node / edge access ────────────────────────────────────────────────────
   #:add-node               ; (dg id type label) → node
   #:add-edge               ; (dg from-id to-id relation) → edge
   #:get-node               ; (dg id) → node | NIL
   #:node-type              ; node → :fact | :rule
   #:node-label             ; node → string
   #:successors             ; (dg node-id) → list of node-ids
   #:predecessors           ; (dg node-id) → list of node-ids

   ;; ── Graph-level operations ────────────────────────────────────────────────
   #:trace->graph           ; (trace) → derivation-graph
   #:graph-depth            ; (dg) → integer
   #:root-nodes             ; (dg) → list of node-ids  (nodes with no predecessors)
   #:leaf-nodes             ; (dg) → list of node-ids  (nodes with no successors)
   #:subgraph-from          ; (dg node-id) → derivation-graph

   ;; ── Structural comparison ─────────────────────────────────────────────────
   #:isomorphic-p           ; (dg1 dg2) → boolean
   #:common-subgraph        ; (dg1 dg2) → derivation-graph | NIL

   ;; ── Raw struct accessors needed by main.lisp / printers ──────────────────
   ;; These are the low-level struct accessors for GRAPH-NODE and GRAPH-EDGE.
   ;; Use NODE-TYPE / NODE-LABEL when you only need the value; use these when
   ;; you need to iterate over the raw edge or node-table collections.
   #:derivation-graph-edges  ; dg → list of graph-edge structs
   #:derivation-graph-node-table  ; dg → hash-table  (same as derivation-graph-raw)
   #:graph-node-type         ; graph-node → :fact | :rule
   #:graph-node-label        ; graph-node → string
   #:graph-edge-from-id      ; graph-edge → symbol
   #:graph-edge-to-id        ; graph-edge → symbol
   #:graph-edge-relation     ; graph-edge → :input-of | :produces

   ;; ── Label helpers ────────────────────────────────────────────────────────
   #:fact-label              ; (fact-id) → string  e.g. "mortal(socrates)"
   #:rule-label              ; (rule-id) → string  e.g. "[rule] modus-ponens"
   ))

;;; Layer 3 — Truth Maintenance System (JTMS)
;;;
;;; Implements a Justification-based Truth Maintenance System after Doyle (1979).
;;;
;;; Every fact that the Inference Engine derives is given a JUSTIFICATION:
;;;   (derived-fact-id  rule-id  (parent-fact-id ...)).
;;;
;;; These justifications form a dependency graph.  When a fact is retracted
;;; (because it was wrong, or a parent was retracted), the TMS:
;;;   1. Locates all justifications that depended on the retracted fact.
;;;   2. Marks those derived facts as "unsupported".
;;;   3. Propagates the retraction recursively down the dependency graph.
;;;   4. At the end, calls jarvis.knowledge:retract-fact for each removed node.
;;;
;;; Contradiction handling:
;;;   When two facts with the CONTRADICTION predicate are both believed,
;;;   the TMS picks the most recently added root assumption and retracts it.

(defpackage :jarvis.truth-maintenance
  (:use :cl :jarvis.knowledge :jarvis.inference)
  (:export
   ;; ── Justification management ─────────────────────────────────────────────
   #:add-justification        ; (derived-id rule-id parent-ids) → justification
   #:justification-for        ; (fact-id) → justification | NIL
   #:supported-p              ; (fact-id) → boolean

   ;; ── Retraction & propagation ─────────────────────────────────────────────
   #:retract-with-support     ; (fact-id) → list of retracted fact-ids
   ;;   Retracts fact and every fact that depended on it.

   ;; ── Contradiction resolution ─────────────────────────────────────────────
   #:check-contradictions     ; () → boolean  — T if contradictions found & resolved
   #:register-contradiction   ; (fact-id-a fact-id-b) → void

   ;; ── Dependency graph access ───────────────────────────────────────────────
   #:dependency-parents       ; (fact-id) → list of fact-ids
   #:dependency-children      ; (fact-id) → list of fact-ids
   #:*justification-table*    ; hash-table: fact-id → justification

   ;; ── TMS reset ────────────────────────────────────────────────────────────
   #:clear-tms                ; () → void  — wipe all TMS tables between runs
   ))

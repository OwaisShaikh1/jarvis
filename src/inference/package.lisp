;;; Layer 2 — Inference Engine
;;;
;;; Implements a simple forward-chaining rule engine inspired by the Rete algorithm.
;;;
;;; The cycle:
;;;   1. Build a candidate list (AGENDA) of rules whose conditions match current facts.
;;;   2. Pop the highest-priority rule from the agenda.
;;;   3. Unify rule variables with matching facts.
;;;   4. If all conditions are satisfied, fire the rule:
;;;        • instantiate the conclusion with the variable bindings.
;;;        • store the new derived fact via jarvis.knowledge:store-fact.
;;;   5. Repeat until the agenda is empty or a goal is reached.
;;;
;;; Cycle detection: a set of "already-fired" (rule-id . binding-hash) pairs
;;; prevents the same instantiation from firing twice in one session.

(defpackage :jarvis.inference
  (:use :cl :jarvis.knowledge)
  (:export
   ;; ── Unification ──────────────────────────────────────────────────────────
   #:+no-bindings+      ; successful empty binding environment
   #:unify              ; (pattern fact &optional bindings) → bindings | NIL
   #:apply-bindings     ; (template bindings) → ground term

   ;; ── Agenda ───────────────────────────────────────────────────────────────
   #:make-agenda        ; () → agenda
   #:agenda-push        ; (agenda rule bindings) → void
   #:agenda-pop         ; (agenda) → (rule . bindings) | NIL
   #:agenda-empty-p     ; (agenda) → boolean
   #:rebuild-agenda     ; (agenda) → void  — re-scan all rules vs current facts

   ;; ── Rule firing ──────────────────────────────────────────────────────────
   #:fire-rule          ; (rule bindings) → (values fact new-p)
   #:run-inference      ; (&key goal max-cycles) → list of new facts
   ;;   goal: optional (predicate &rest args) pattern; stops when matched.
   ;;   max-cycles: safety cap to prevent infinite loops.

   ;; ── Event callbacks (used by Trace Recorder) ─────────────────────────────
   #:*on-rule-fired*    ; parameter: (rule bindings new-fact new-p) → void
   #:*on-cycle-end*     ; parameter: (cycle-number agenda-size) → void
   ))

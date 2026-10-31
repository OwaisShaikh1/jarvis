;;; Layer 1 — Knowledge Representation
;;;
;;; This package owns the three core symbolic databases:
;;;   FACT-DB   — ground-level truths that the system currently believes.
;;;   RULE-DB   — conditional production rules of the form (conditions → conclusion).
;;;   PRINCIPLE-DB — high-priority shortcut rules promoted by the Principle Optimizer.
;;;
;;; All other layers READ from these databases but only write through the
;;; functions exported here, keeping mutation centralised and auditable.

(defpackage :jarvis.knowledge
  (:use :cl)
  (:export
   ;; ── Fact constructors / accessors ──────────────────────────────────────
   #:make-fact          ; (predicate &rest args) → fact
   #:rule-error
   #:rule-error-message
   #:fact-id            ; fact → symbol
   #:fact-predicate     ; fact → symbol
   #:fact-args          ; fact → list
  #:fact-negative-p    ; fact → boolean
   #:fact-derived-p     ; fact → boolean  (was this inferred, not asserted?)
   #:fact-usage-count   ; fact → integer
   #:fact-last-accessed ; fact → universal-time

   ;; ── Rule constructors / accessors ──────────────────────────────────────
   #:make-rule          ; (name conditions conclusion) → rule
   #:rule-id            ; rule → symbol
   #:rule-name          ; rule → symbol
   #:rule-conditions    ; rule → list of patterns
   #:rule-conclusion    ; rule → pattern
  #:rule-negative-p    ; rule → boolean  (does the conclusion mean a negative fact?)
   #:rule-priority      ; rule → integer  (higher fires first)
   #:rule-usage-count   ; rule → integer

   ;; ── Principle constructors / accessors ─────────────────────────────────
   #:make-principle     ; (name score macro-rule) → principle
   #:principle-id       ; principle → symbol
   #:principle-name     ; principle → symbol
   #:principle-score    ; principle → float
   #:principle-rule     ; principle → rule

   ;; ── Database query / mutation ───────────────────────────────────────────
   #:store-fact         ; (fact) → fact           — add to FACT-DB
   #:retract-fact       ; (fact-id) → boolean     — remove from FACT-DB
   #:store-rule         ; (rule) → rule           — add to RULE-DB
   #:store-principle    ; (principle) → principle — add to PRINCIPLE-DB
   #:lookup-facts       ; (&key predicate) → list of facts
   #:lookup-rules       ; (&key predicate) → list of rules (sorted by priority)
   #:all-facts          ; () → list
   #:all-rules          ; () → list
   #:all-principles     ; () → list
   #:fact-exists-p      ; (predicate &rest args) → boolean
   #:touch-fact         ; (fact-id) → void       — update usage stats

   ;; ── Index structures (shared by inference engine) ───────────────────────
   #:*fact-db*
   #:*rule-db*
   #:*principle-db*
   #:clear-databases    ; () → void  — wipe everything (useful for tests)
   ))

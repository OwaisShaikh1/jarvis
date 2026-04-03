;;; Layer 4 — Trace Recorder
;;;
;;; Records every inference episode as a structured TRACE object.
;;;
;;; A TRACE represents one complete reasoning session:
;;;   • start-state  — snapshot of the fact database before inference began.
;;;   • end-state    — snapshot after inference completed.
;;;   • steps        — ordered list of TRACE-STEPs.
;;;   • depth        — maximum derivation depth reached.
;;;
;;; A TRACE-STEP records one rule firing:
;;;   • rule-id      — which rule fired.
;;;   • input-ids    — fact IDs that matched the rule conditions.
;;;   • output-id    — the newly derived fact ID.
;;;   • depth        — derivation depth of this step.
;;;
;;; The trace recorder attaches itself to the inference engine via the
;;; *ON-RULE-FIRED* callback hook, so no polling is required.
;;;
;;; Completed traces are keyed by a unique session ID and stored in
;;; *TRACE-STORE*, ready for the Abstraction Engine to consume.

(defpackage :jarvis.trace
  (:use :cl :jarvis.knowledge :jarvis.inference)
  (:export
   ;; ── Trace-step structure ─────────────────────────────────────────────────
   #:make-trace-step       ; (rule-id input-ids output-id depth) → trace-step
   #:trace-step-rule-id    ; trace-step → symbol
   #:trace-step-input-ids  ; trace-step → list
   #:trace-step-output-id  ; trace-step → symbol
   #:trace-step-depth      ; trace-step → integer

   ;; ── Trace structure ──────────────────────────────────────────────────────
   #:make-trace            ; (session-id) → trace
   #:trace-session-id      ; trace → symbol
   #:trace-start-state     ; trace → list of facts
   #:trace-end-state       ; trace → list of facts
   #:trace-steps           ; trace → list of trace-steps
   #:trace-depth           ; trace → integer
   #:trace-step-count      ; trace → integer

   ;; ── Session control ──────────────────────────────────────────────────────
   #:begin-trace-session   ; () → session-id   — start recording
   #:end-trace-session     ; (session-id) → trace  — stop & store
   #:current-session-id    ; () → symbol | NIL

   ;; ── Trace store ──────────────────────────────────────────────────────────
   #:*trace-store*         ; hash-table: session-id → trace
   #:lookup-trace          ; (session-id) → trace | NIL
   #:all-traces            ; () → list of traces
   #:clear-traces          ; () → void
   ))

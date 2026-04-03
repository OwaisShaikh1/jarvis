;;; =============================================================================
;;; Layer 4 — Trace Recorder
;;; File: src/trace/trace.lisp
;;;
;;; Records every inference session as a structured REASONING-TRACE object
;;; that the Graph Representation layer (Layer 5) will convert into a DAG,
;;; and that the Abstraction Engine (Layer 6) will analyse for patterns.
;;;
;;; NOTE: We use the name REASONING-TRACE (not TRACE) because CL:TRACE is
;;; a reserved symbol in the COMMON-LISP package and cannot be redefined.
;;;
;;; Session lifecycle:
;;;   1.  Call BEGIN-TRACE-SESSION before starting inference.
;;;       Returns a session-id that identifies this recording.
;;;   2.  Run inference normally.  The hook captures each step automatically.
;;;   3.  Call END-TRACE-SESSION with the session-id after inference finishes.
;;;       This closes the session, computes summary metrics, and stores the
;;;       completed REASONING-TRACE in *TRACE-STORE*.
;;; =============================================================================

(in-package :jarvis.trace)


;;; ---------------------------------------------------------------------------
;;; Section 1 — Trace-step structure
;;;
;;; A TRACE-STEP is a snapshot of one rule firing:
;;;   RULE-ID    — which rule produced the output.
;;;   INPUT-IDS  — fact IDs that matched the rule conditions.
;;;   OUTPUT-ID  — fact ID of the newly derived fact.
;;;   DEPTH      — derivation depth (hops from root assumptions).
;;; ---------------------------------------------------------------------------

(defstruct (trace-step (:constructor %make-trace-step))
  "One inference step: a single rule firing recorded in full."
  rule-id     ; symbol
  input-ids   ; list of symbols
  output-id   ; symbol
  depth)      ; non-negative integer

(defun make-trace-step (rule-id input-ids output-id depth)
  "Construct a TRACE-STEP. All arguments are mandatory."
  (%make-trace-step :rule-id   rule-id
                    :input-ids input-ids
                    :output-id output-id
                    :depth     depth))


;;; ---------------------------------------------------------------------------
;;; Section 2 — Reasoning-trace structure
;;;
;;; A REASONING-TRACE records a complete inference session. It is built
;;; incrementally as steps arrive through the *ON-RULE-FIRED* hook, then
;;; finalised by END-TRACE-SESSION.
;;; ---------------------------------------------------------------------------

(defstruct (reasoning-trace (:constructor %make-reasoning-trace))
  "A complete recording of one forward-chaining inference session."
  session-id   ; symbol, e.g. SESSION-7
  start-state  ; list of facts at session open
  end-state    ; list of facts at session close (filled by END-TRACE-SESSION)
  (steps nil :type list)        ; list of TRACE-STEPs, populated incrementally
  (depth 0 :type integer)       ; max derivation depth seen so far
  (step-count 0 :type integer)) ; total rule firings this session


;;; ---------------------------------------------------------------------------
;;; Section 3 — Session state
;;; ---------------------------------------------------------------------------

(defvar *active-session* nil
  "The REASONING-TRACE currently being recorded, or NIL when no session is open.")

(defvar *trace-store* (make-hash-table :test #'eq)
  "Archive of all completed REASONING-TRACEs. Key: session-id. Value: struct.")

(defvar *session-counter* 0
  "Monotonic counter for minting unique session IDs.")

(defun next-session-id ()
  "Return a fresh symbol like SESSION-1, SESSION-2, ..."
  (intern (format nil "SESSION-~A" (incf *session-counter*)) :jarvis.trace))

(defun current-session-id ()
  "Return the session-id of the currently active session, or NIL."
  (when *active-session*
    (reasoning-trace-session-id *active-session*)))


;;; ---------------------------------------------------------------------------
;;; Section 4 — Depth estimation
;;; ---------------------------------------------------------------------------

(defun estimate-depth (input-ids)
  "Compute the derivation depth of a fact produced from INPUT-IDS.
   Returns 1 + max depth of inputs. Root assumptions count as depth 0."
  (if (null input-ids)
      0
      (1+ (loop for id in input-ids
                for fact = (gethash id jarvis.knowledge:*fact-db*)
                maximize (if (and fact (jarvis.knowledge:fact-derived-p fact))
                             (or (loop for step in
                                       (when *active-session*
                                         (reasoning-trace-steps *active-session*))
                                       when (eq (trace-step-output-id step) id)
                                         return (trace-step-depth step))
                                 0)
                             0)))))


;;; ---------------------------------------------------------------------------
;;; Section 5 — On-rule-fired hook handler
;;;
;;; The *ON-RULE-FIRED* hook is called by the inference engine immediately
;;; after a rule fires.  Its signature is:
;;;   (lambda (rule bindings new-fact) ...)
;;;
;;; We use the BINDINGS to reconstruct the exact set of facts that matched
;;; the rule conditions — each condition is grounded by substituting the
;;; bindings and then looked up in *FACT-DB*.  This gives us precise
;;; provenance for each derivation step, which the TMS later uses to
;;; compute correct cascade retractions.
;;; ---------------------------------------------------------------------------

(defun inputs-from-bindings (rule bindings)
  "Return the list of fact-ids that specifically matched RULE's conditions
   under the given BINDINGS.  Works by grounding each condition pattern
   with APPLY-BINDINGS, then finding the corresponding fact in *FACT-DB*.
   This is more precise than scanning all derived facts and avoids
   false parent relationships in the TMS dependency graph."
  (loop for condition in (jarvis.knowledge:rule-conditions rule)
        ;; Ground the pattern: replace every ?variable with its bound value.
        for ground-pattern = (apply-bindings condition bindings)
        for predicate      = (first ground-pattern)
        for args           = (rest  ground-pattern)
        ;; Find the unique fact that matches this ground pattern.
        for match = (find-if
                     (lambda (f)
                       (and (eq    (jarvis.knowledge:fact-predicate f) predicate)
                            (equal (jarvis.knowledge:fact-args f)      args)))
                     (jarvis.knowledge:lookup-facts :predicate predicate))
        ;; A match should always exist at this point — the inference engine
        ;; only fires rules whose conditions are already satisfied.
        when match
          collect (jarvis.knowledge:fact-id match)))

(defun make-step-recorder ()
  "Return a closure for jarvis.inference:*ON-RULE-FIRED*.
   Records each rule firing as a TRACE-STEP in the active session."
  (lambda (rule bindings new-fact)
    (when *active-session*
      ;; Precise input tracking: only the facts that matched this rule's
      ;; specific conditions under these bindings.
      (let* ((input-ids  (inputs-from-bindings rule bindings))
             (output-id  (jarvis.knowledge:fact-id new-fact))
             (depth      (estimate-depth input-ids))
             (step       (make-trace-step
                          (jarvis.knowledge:rule-id rule)
                          input-ids
                          output-id
                          depth)))
        ;; Append step in chronological order.
        (setf (reasoning-trace-steps *active-session*)
              (append (reasoning-trace-steps *active-session*) (list step)))
        ;; Update running maximum depth.
        (when (> depth (reasoning-trace-depth *active-session*))
          (setf (reasoning-trace-depth *active-session*) depth))
        ;; Maintain cached step count.
        (incf (reasoning-trace-step-count *active-session*))))))


;;; ---------------------------------------------------------------------------
;;; Section 6 — Session control
;;; ---------------------------------------------------------------------------

(defun begin-trace-session ()
  "Open a new trace session. Snapshots facts as start-state, installs the
   hook, and returns the session-id."
  (when *active-session*
    (format t "[trace] WARNING: session ~A still open; closing it.~%"
            (current-session-id))
    (end-trace-session (current-session-id)))
  (let* ((sid    (next-session-id))
         (rtrace (%make-reasoning-trace
                  :session-id  sid
                  :start-state (copy-list (jarvis.knowledge:all-facts)))))
    (setf *active-session* rtrace)
    (setf jarvis.inference:*on-rule-fired* (make-step-recorder))
    (format t "[trace] Session ~A started. ~A facts in start-state.~%"
            sid (length (reasoning-trace-start-state rtrace)))
    sid))

(defun end-trace-session (session-id)
  "Close SESSION-ID: snapshot end-state, remove hook, archive, return trace."
  (unless (and *active-session*
               (eq (reasoning-trace-session-id *active-session*) session-id))
    (error "No active session with id ~A" session-id))
  (setf (reasoning-trace-end-state *active-session*)
        (copy-list (jarvis.knowledge:all-facts)))
  (setf jarvis.inference:*on-rule-fired* nil)
  (let ((completed *active-session*))
    (setf (gethash session-id *trace-store*) completed)
    (setf *active-session* nil)
    (format t "[trace] Session ~A closed. ~A steps, max depth ~A.~%"
            session-id
            (reasoning-trace-step-count completed)
            (reasoning-trace-depth completed))
    completed))


;;; ---------------------------------------------------------------------------
;;; Section 7 — Trace store access
;;; ---------------------------------------------------------------------------

(defun lookup-trace (session-id)
  "Return the REASONING-TRACE for SESSION-ID, or NIL."
  (gethash session-id *trace-store*))

(defun all-traces ()
  "Return a list of all completed REASONING-TRACE structs."
  (loop for rtrace being the hash-values of *trace-store* collect rtrace))

(defun clear-traces ()
  "Wipe *TRACE-STORE* and reset the session counter."
  (clrhash *trace-store*)
  (setf *session-counter* 0)
  (values))


;;; ---------------------------------------------------------------------------
;;; Section 8 — Short-name accessor aliases
;;;
;;; The main struct is called REASONING-TRACE (not TRACE) because CL:TRACE is
;;; a reserved built-in function and cannot be redefined.  All other layers
;;; interact with traces through these short-name wrappers so they never need
;;; to spell out the REASONING-TRACE- prefix.  If you ever rename the struct,
;;; only this section needs updating.
;;; ---------------------------------------------------------------------------

(defun trace-session-id (rt)
  "Return the unique session-id symbol of REASONING-TRACE RT."
  (reasoning-trace-session-id rt))

(defun trace-start-state (rt)
  "Return the list of FACT structs snapshotted when the session opened."
  (reasoning-trace-start-state rt))

(defun trace-end-state (rt)
  "Return the list of FACT structs snapshotted when the session closed."
  (reasoning-trace-end-state rt))

(defun trace-steps (rt)
  "Return the ordered list of TRACE-STEP structs recorded in this session."
  (reasoning-trace-steps rt))

(defun trace-depth (rt)
  "Return the maximum derivation depth reached during this session."
  (reasoning-trace-depth rt))

(defun trace-step-count (rt)
  "Return the total number of rule firings recorded in this session."
  (reasoning-trace-step-count rt))
;;; =============================================================================
;;; Layer 2 — Inference Engine
;;; File: src/inference/inference.lisp
;;;
;;; Implements forward-chaining rule application.
;;;
;;; Key concepts:
;;;
;;;   VARIABLE  — any atom whose name begins with "?" is treated as a logic
;;;               variable during pattern matching.  E.g. ?X, ?WHO, ?N.
;;;
;;;   BINDINGS  — an association list ((var . value) ...) built up as the
;;;               unifier matches a pattern against a ground fact.
;;;               Example: ((?X . SOCRATES) (?Y . ATHENS))
;;;
;;;   UNIFICATION — the process of deciding whether a pattern can be made
;;;               identical to a ground fact under some binding.  Variables
;;;               can bind to any symbol; ground symbols must match exactly.
;;;
;;;   AGENDA    — a priority queue of (rule . bindings) pairs that are ready
;;;               to fire.  Pairs are ordered by the rule's priority (higher
;;;               fires first).  A fired-set prevents the same instantiation
;;;               from being re-triggered in the same run-inference call.
;;;
;;;   INFERENCE CYCLE:
;;;     1.  Scan all rules; for each rule try to satisfy every condition
;;;         pattern against current facts using MATCH-CONDITIONS.
;;;     2.  For each fully-matched rule, push (rule . bindings) onto the agenda.
;;;     3.  Pop the top agenda entry.  Check the fired-set to skip duplicates.
;;;     4.  Call FIRE-RULE, which instantiates the conclusion and stores it.
;;;     5.  Notify the *ON-RULE-FIRED* hook (used by the Trace Recorder).
;;;     6.  Repeat from step 1 until the agenda is empty, the optional GOAL
;;;         pattern is satisfied, or MAX-CYCLES is reached.
;;; =============================================================================

(in-package :jarvis.inference)


;;; ---------------------------------------------------------------------------
;;; Section 1 — Logic variable helpers
;;; ---------------------------------------------------------------------------

(defun variable-p (x)
  "Return T if X is a logic variable — a symbol whose name starts with '?'."
  (and (symbolp x)
       (char= (char (symbol-name x) 0) #\?)))

(defun lookup-binding (var bindings)
  "Return the value bound to VAR in BINDINGS, or NIL if unbound.
   BINDINGS is an alist of (variable . value) pairs."
  (cdr (assoc var bindings :test #'eq)))


;;; ---------------------------------------------------------------------------
;;; Section 2 — Unification
;;;
;;; UNIFY tries to extend BINDINGS so that PATTERN matches FACT-ARGS.
;;; PATTERN is a list of atoms/variables; FACT-ARGS is a list of ground atoms.
;;;
;;; It walks both lists in parallel:
;;;   • If the pattern element is a variable:
;;;       – If already bound, the bound value must equal the fact element.
;;;       – If unbound, extend bindings with (var . fact-element).
;;;   • If the pattern element is a ground symbol:
;;;       – It must EQ the corresponding fact element.
;;; Returns the (possibly extended) bindings on success, or NIL on failure.
;;; ---------------------------------------------------------------------------

(defun unify (pattern fact-args bindings)
  "Attempt to unify PATTERN (a list with possible ?variables) against
   FACT-ARGS (a ground list of symbols).
   BINDINGS is the current variable environment (an alist).
   Returns extended bindings on success, NIL on failure."
  (cond
    ;; Both lists exhausted simultaneously — success.
    ((and (null pattern) (null fact-args))
     bindings)
    ;; One list is longer than the other — arity mismatch.
    ((or (null pattern) (null fact-args))
     nil)
    (t
     (let ((p (car pattern))
           (f (car fact-args)))
       (cond
         ;; Pattern element is a variable.
         ((variable-p p)
          (let ((bound-val (lookup-binding p bindings)))
            (if bound-val
                ;; Variable already bound — the value must match.
                (when (equal bound-val f)
                  (unify (cdr pattern) (cdr fact-args) bindings))
                ;; Variable is free — bind it and continue.
                (unify (cdr pattern) (cdr fact-args)
                       (acons p f bindings)))))
         ;; Pattern element is a ground atom — must match exactly.
         ((equal p f)
          (unify (cdr pattern) (cdr fact-args) bindings))
         ;; No match.
         (t nil))))))

(defun apply-bindings (template bindings)
  "Replace every logic variable in TEMPLATE with its value from BINDINGS.
   TEMPLATE is a flat list of atoms/variables (a rule conclusion pattern).
   Unbound variables are left in place — the caller should treat such a
   result as an incomplete instantiation and discard it."
  (mapcar (lambda (element)
            (if (variable-p element)
                ;; Substitute the bound value, or leave the variable as-is.
                (or (lookup-binding element bindings) element)
                element))
          template))


;;; ---------------------------------------------------------------------------
;;; Section 3 — Condition matching
;;;
;;; A rule may have multiple conditions.  We must find a consistent set of
;;; bindings that satisfies ALL conditions simultaneously.
;;;
;;; MATCH-CONDITIONS uses a recursive search:
;;;   • Take the first condition pattern.
;;;   • Try to unify it against every fact with a matching predicate.
;;;   • For each successful unification, recurse on the remaining conditions
;;;     using the extended bindings.
;;; This is essentially a mini Prolog SLD resolution step.
;;; ---------------------------------------------------------------------------

(defun match-conditions (conditions bindings)
  "Return a list of all binding environments under which every pattern in
   CONDITIONS is satisfiable against the current *FACT-DB*.
   Each returned element is a complete alist of (variable . value) pairs.
   Returns NIL if no satisfying binding exists."
  (if (null conditions)
      ;; Base case — all conditions satisfied; return the current bindings.
      (list bindings)
      ;; The first element of a pattern is the predicate — use the index.
      (let* ((pattern      (car conditions))
             (rest-conds   (cdr conditions))
             (predicate    (first pattern))
             (pattern-args (rest pattern)))
        ;; Walk every fact matching the pattern's predicate.
          (loop for fact in (jarvis.knowledge:lookup-facts :predicate predicate
                           :negative-p nil)
              ;; Stamp usage statistics on every accessed fact.
              do (jarvis.knowledge:touch-fact (jarvis.knowledge:fact-id fact))
              ;; Collect all successful sub-matches; skip mismatches silently.
              nconcing
              (let ((new-bindings (unify pattern-args
                                         (jarvis.knowledge:fact-args fact)
                                         bindings)))
                (if new-bindings
                    ;; Unification succeeded — recurse on remaining conditions.
                    (match-conditions rest-conds new-bindings)
                    nil))))))

;;; ---------------------------------------------------------------------------
;;; Section 4 — Agenda
;;;
;;; The agenda is a sorted list of (priority rule . bindings) triples.
;;; Using a simple sorted list is adequate for the sizes expected here
;;; (hundreds of rules, not millions).
;;; ---------------------------------------------------------------------------

(defstruct (agenda (:constructor %make-agenda))
  "Priority queue of (rule . bindings) pairs ready to fire.
   Items are kept sorted by descending rule priority.
   The struct constructor is named %MAKE-AGENDA so there is no conflict with
   the exported MAKE-AGENDA function defined below."
  (items nil :type list))

(defun make-agenda ()
  "Construct an empty AGENDA.  Wraps %MAKE-AGENDA so callers use a stable
   exported name regardless of the internal struct constructor."
  (%make-agenda))

(defun agenda-push (agenda rule bindings)
  "Insert (RULE . BINDINGS) into AGENDA, maintaining descending priority order."
  (push (cons rule bindings) (agenda-items agenda))
  ;; Re-sort after every push.  A heap would be O(log n) but this is simpler.
  (setf (agenda-items agenda)
        (sort (agenda-items agenda)
              #'> :key (lambda (item) (jarvis.knowledge:rule-priority (car item))))))

(defun agenda-pop (agenda)
  "Remove and return the highest-priority (RULE . BINDINGS) pair, or NIL if empty."
  (pop (agenda-items agenda)))

(defun agenda-empty-p (agenda)
  "Return T if there are no pending rule instantiations."
  (null (agenda-items agenda)))

(defun rebuild-agenda (agenda)
  "Clear AGENDA and re-populate it by matching all rules against current facts.
   Called at the start of each inference cycle to pick up newly derived facts."
  (setf (agenda-items agenda) nil)
  (dolist (rule (jarvis.knowledge:all-rules))
    ;; Try to satisfy all conditions of this rule.
    (dolist (bindings (match-conditions (jarvis.knowledge:rule-conditions rule) nil))
      (agenda-push agenda rule bindings))))


;;; ---------------------------------------------------------------------------
;;; Section 5 — Rule firing
;;; ---------------------------------------------------------------------------

(defun fire-rule (rule bindings)
  "Instantiate RULE's conclusion under BINDINGS and store the resulting fact.
   Returns the newly derived FACT struct.
   The fact's DERIVED-P flag is set to T so the TMS knows it was inferred."
  ;; Substitute variables in the conclusion template with bound values.
  (let* ((conclusion-template (jarvis.knowledge:rule-conclusion rule))
         (ground-conclusion   (apply-bindings conclusion-template bindings)))
    ;; The conclusion list is (predicate arg1 arg2 ...).
    (let* ((predicate (first ground-conclusion))
           (args      (rest ground-conclusion))
           ;; Build the new fact.
           (new-fact  (apply #'jarvis.knowledge:make-fact predicate args)))
      ;; Mark as inferred so the TMS can track its justification.
      (setf (jarvis.knowledge:fact-derived-p new-fact) t)
    ;; Propagate rule polarity into the derived fact.
    (setf (jarvis.knowledge:fact-negative-p new-fact)
      (jarvis.knowledge:rule-negative-p rule))
      ;; Increment the rule's usage counter.
      (incf (jarvis.knowledge:rule-usage-count rule))
      ;; Store (returns existing if duplicate).
      (jarvis.knowledge:store-fact new-fact))))


;;; ---------------------------------------------------------------------------
;;; Section 6 — Callback hooks
;;;
;;; These special variables hold functions that other layers can install to
;;; receive notifications without creating import cycles.
;;;
;;;   *ON-RULE-FIRED*  is called after every successful rule firing.
;;;   *ON-CYCLE-END*   is called after every inference cycle (one pass over
;;;                    the agenda until empty).
;;;
;;; The Trace Recorder installs its listener into *ON-RULE-FIRED*.
;;; The Meta Controller can install progress monitors into *ON-CYCLE-END*.
;;; ---------------------------------------------------------------------------

(defparameter *on-rule-fired* nil
  "Optional callback: (lambda (rule bindings new-fact) ...).
   Called immediately after a rule fires and its conclusion is stored.
   Install a function here to observe every derivation step (e.g., trace recording).")

(defparameter *on-cycle-end* nil
  "Optional callback: (lambda (cycle-number agenda-size) ...).
   Called at the end of each inference cycle, after the agenda is rebuilt.")


;;; ---------------------------------------------------------------------------
;;; Section 7 — Main inference loop
;;; ---------------------------------------------------------------------------

(defun run-inference (&key goal (max-cycles 1000))
  "Execute forward-chaining inference until one of three stopping conditions:
     1. The AGENDA is empty (no more applicable rules).
     2. GOAL is satisfied: GOAL is a ground fact list (predicate arg...) and
        FACT-EXISTS-P returns true for it.
     3. MAX-CYCLES is reached (default 1000) — a safety valve for cyclic rules.

   Returns a list of all newly derived FACT structs produced during this call."
  (let ((agenda      (make-agenda))
        ;; The fired-set prevents the same (rule . bindings) from firing twice.
        (fired-set   (make-hash-table :test #'equal))
        (new-facts   nil)
        (cycle       0))

    (loop
      ;; Stopping condition 3 — exceeded cycle cap.
      (when (>= cycle max-cycles)
        (format t "[inference] WARNING: max-cycles (~A) reached.~%" max-cycles)
        (return))

      ;; Stopping condition 2 — goal already in the fact database.
      (when (and goal
                 (apply #'jarvis.knowledge:fact-exists-p goal))
        (return))

      ;; Rebuild agenda from all current facts each cycle.
      ;; This is O(rules × facts-per-predicate) but keeps the design simple.
      (rebuild-agenda agenda)

      ;; If nothing is applicable we are done.
      (when (agenda-empty-p agenda)
        (return))

      ;; Fire every entry on the agenda that hasn't been fired yet.
      (let ((fired-this-cycle 0))
        (loop until (agenda-empty-p agenda)
              for (rule . bindings) = (agenda-pop agenda)
              ;; Use a hash of the rule ID + binding string as the de-dup key.
              for fired-key = (cons (jarvis.knowledge:rule-id rule)
                                    (format nil "~S" bindings))
              unless (gethash fired-key fired-set)
                do (let ((new-fact (fire-rule rule bindings)))
                     ;; Mark as fired to prevent re-triggering.
                     (setf (gethash fired-key fired-set) t)
                     (incf fired-this-cycle)
                     ;; Collect the derived fact.
                     (push new-fact new-facts)
                     ;; Notify subscribers (e.g., the Trace Recorder).
                     (when *on-rule-fired*
                       (funcall *on-rule-fired* rule bindings new-fact))))

        ;; If every agenda item was already seen, inference has converged.
        (when (zerop fired-this-cycle)
          (return)))

      ;; Notify cycle-end subscribers and advance the counter.
      (when *on-cycle-end*
        (funcall *on-cycle-end* cycle (length (agenda-items agenda))))
      (incf cycle))

    ;; Return the deduplicated list of new facts.
    (remove-duplicates new-facts :test #'eq)))

;;; =============================================================================
;;; Layer 1 — Knowledge Representation
;;; File: src/knowledge/knowledge.lisp
;;;
;;; This file implements the three symbolic databases that the rest of the
;;; system reads and writes:
;;;
;;;   *FACT-DB*       — hash-table of all facts currently believed (ground truths
;;;                     and derived truths alike).
;;;   *RULE-DB*       — hash-table of all production rules.
;;;   *PRINCIPLE-DB*  — hash-table of promoted high-value macro rules.
;;;
;;; Additionally, two secondary indexes are maintained:
;;;   *PREDICATE-FACT-INDEX*  — predicate symbol → list of fact IDs
;;;   *PREDICATE-RULE-INDEX*  — head predicate symbol → list of rule IDs
;;;
;;; These indexes make pattern-matching in the Inference Engine O(k) instead
;;; of O(n) where k is the number of facts/rules sharing a predicate.
;;;
;;; ID generation is handled by a simple monotonically-increasing counter so
;;; IDs are stable, unique, and easy to read in printed output.
;;; =============================================================================

(in-package :jarvis.knowledge)


;;; ---------------------------------------------------------------------------
;;; Section 1 — ID counter
;;;
;;; Every stored object (fact, rule, principle) gets a unique symbol of the
;;; form FACT-42, RULE-7, PRINCIPLE-3.  The counter is never reset during a
;;; session so IDs are globally unique within a process image.
;;; ---------------------------------------------------------------------------

(defvar *id-counter* 0
  "Monotonically increasing counter used to mint unique object IDs.")

(defun next-id (prefix)
  "Return a freshly interned symbol like FACT-42.
   PREFIX should be a string such as \"FACT\", \"RULE\", or \"PRINCIPLE\"."
  (intern (format nil "~A-~A" prefix (incf *id-counter*)) :jarvis.knowledge))


;;; ---------------------------------------------------------------------------
;;; Section 2 — Fact structure
;;;
;;; A FACT is the atomic unit of knowledge.  It records:
;;;   PREDICATE    — the relation name, e.g. MORTAL.
;;;   ARGS         — zero or more ground symbolic arguments, e.g. (SOCRATES).
;;;   NEGATIVE-P   — T if this fact is explicitly negative (an excluded state).
;;;   DERIVED-P    — was this asserted by the user (NIL) or derived by a rule (T)?
;;;   USAGE-COUNT  — incremented by TOUCH-FACT each time another module reads it.
;;;   LAST-ACCESSED — a universal-time timestamp updated on every access.
;;; ---------------------------------------------------------------------------

(defstruct (fact (:constructor %make-fact))
  "A single ground-level belief held by the system."
  id           ; symbol, e.g. FACT-1
  predicate    ; symbol, e.g. MORTAL
  args         ; list of symbols, e.g. (SOCRATES)
  (negative-p nil :type boolean)
  derived-p    ; boolean — T if inferred by a rule, NIL if asserted by a user
  (usage-count 0 :type integer)
  (last-accessed 0 :type integer))  ; universal-time from GET-UNIVERSAL-TIME

(defun make-fact (predicate &rest args)
  "Construct a new FACT.  The caller is responsible for storing it via STORE-FACT.
   PREDICATE must be a symbol.  ARGS are the relational arguments.
   DERIVED-P defaults to NIL; set the slot directly if constructing an inferred fact."
  (%make-fact :id        (next-id "FACT")
              :predicate predicate
              :args      args
              :derived-p nil
              :last-accessed (get-universal-time)))


;;; ---------------------------------------------------------------------------
;;; Section 3 — Rule structure
;;;
;;; A RULE encodes a production rule:  IF conditions THEN conclusion.
;;;
;;;   CONDITIONS — a list of patterns.  Each pattern is a list whose first
;;;                element is a predicate symbol and whose remaining elements
;;;                are either ground symbols or logic variables (symbols
;;;                starting with "?").
;;;                Example: ((mortal ?x) (human ?x))
;;;
;;;   CONCLUSION — a single pattern in the same format.
;;;                Example: (dies ?x)
;;;
;;;   NEGATIVE-P — T if the rule's conclusion should be stored as a negative
;;;                fact.  The conclusion pattern itself is normalized to the
;;;                underlying predicate/args form.
;;;
;;;   PRIORITY   — integer, higher fires first.  Principles get very high
;;;                priority so they short-circuit deep reasoning chains.
;;; ---------------------------------------------------------------------------

(defstruct (rule (:constructor %make-rule))
  "A production rule:  IF all CONDITIONS match facts THEN assert CONCLUSION."
  id           ; symbol, e.g. RULE-2
  name         ; human-readable symbol, e.g. MODUS-PONENS
  conditions   ; list of patterns with optional ?variables
  conclusion   ; single pattern
  (negative-p nil :type boolean)
  (priority 0 :type integer)
  (usage-count 0 :type integer))

(defun normalize-rule-conclusion (conclusion)
  "Return two values: a normalized positive conclusion pattern and a negative flag.
   Accepts negation wrappers of the form (! predicate args...) or (not predicate args...)."
  (cond
    ((and (consp conclusion)
    (string= (symbol-name (first conclusion)) "!"))
  (if (null (rest conclusion))
      (error "Negative rule conclusion (! ...) requires a predicate and optional args.")
      (values (rest conclusion) t)))
    ((and (consp conclusion)
    (string= (symbol-name (first conclusion)) "NOT"))
  (if (null (rest conclusion))
      (error "Negative rule conclusion (not ...) requires a predicate and optional args.")
      (values (rest conclusion) t)))
    ((and (consp conclusion)
          (symbolp (first conclusion))
    (> (length (symbol-name (first conclusion))) 1)
    (char= (char (symbol-name (first conclusion)) 0) #\!))
  (values (cons (intern (subseq (symbol-name (first conclusion)) 1)
            (or (symbol-package (first conclusion)) *package*))
          (rest conclusion))
       t))
    ((and (consp conclusion)
    (symbolp (first conclusion))
    (char= (char (symbol-name (first conclusion)) 0) #\!))
  (error "Negative rule conclusion must be either (! predicate args...) or (!predicate args...) with a real predicate name."))
    (t
     (values conclusion nil))))

(define-condition rule-error (error)
  ((message :initarg :message :reader rule-error-message)))

(defun logic-variable-p (term)
  "Return T when TERM is a non-empty symbol beginning with ?. "
  (and (symbolp term)
       (let ((name (symbol-name term)))
         (and (plusp (length name))
              (char= (char name 0) #\?)))))

(defun pattern-variables (pattern)
  "Collect all logic variables occurring anywhere in PATTERN."
  (remove-duplicates
   (labels ((walk (term)
              (cond
                ((logic-variable-p term) (list term))
                ((consp term) (append (walk (car term))
                                      (walk (cdr term))))
                (t nil))))
     (walk pattern))
   :test #'eq))

(defun make-rule (name conditions conclusion)
  "Construct a new RULE.  NAME is a descriptive symbol.
   CONDITIONS is a list of patterns; CONCLUSION is a single pattern.
   The rule is not stored — call STORE-RULE to register it in *RULE-DB*."
  (multiple-value-bind (normalized-conclusion negative-p)
      (normalize-rule-conclusion conclusion)
    (let ((condition-variables
            (remove-duplicates
             (mapcan #'pattern-variables conditions)
             :test #'eq))
          (conclusion-variables (pattern-variables normalized-conclusion)))
      (dolist (variable conclusion-variables)
        (unless (member variable condition-variables :test #'eq)
          (error 'rule-error
                 :message (format nil
                                  "Conclusion variable ~A is not bound by a condition."
                                  variable)))))
    (%make-rule :id         (next-id "RULE")
                :name       name
                :conditions conditions
                :conclusion normalized-conclusion
                :negative-p negative-p)))


;;; ---------------------------------------------------------------------------
;;; Section 4 — Principle structure
;;;
;;; A PRINCIPLE wraps a rule that has been promoted by the Principle Optimizer
;;; because it provides a substantial shortcut.  It carries the optimiser
;;; score so the Meta Controller can rank principles.
;;; ---------------------------------------------------------------------------

(defstruct (principle (:constructor %make-principle))
  "A high-value macro rule promoted to the principle layer."
  id     ; symbol, e.g. PRINCIPLE-1
  name   ; human-readable symbol
  score  ; float — computed by Principle Optimizer
  rule)  ; the underlying RULE struct

(defun make-principle (name score macro-rule)
  "Construct a PRINCIPLE wrapping MACRO-RULE with the given SCORE.
   Call STORE-PRINCIPLE to register it in *PRINCIPLE-DB*."
  (%make-principle :id    (next-id "PRINCIPLE")
                   :name  name
                   :score score
                   :rule  macro-rule))


;;; ---------------------------------------------------------------------------
;;; Section 5 — Databases and indexes
;;; ---------------------------------------------------------------------------

(defvar *fact-db* (make-hash-table :test #'eq)
  "Primary store of all current facts.  Key: fact-id symbol.  Value: FACT struct.")

(defvar *rule-db* (make-hash-table :test #'eq)
  "Primary store of all rules.  Key: rule-id symbol.  Value: RULE struct.")

(defvar *principle-db* (make-hash-table :test #'eq)
  "Primary store of all principles.  Key: principle-id symbol.  Value: PRINCIPLE struct.")

(defvar *predicate-fact-index* (make-hash-table :test #'eq)
  "Secondary index.  Key: predicate symbol.  Value: list of fact-id symbols.
   Allows the inference engine to quickly find facts matching a given predicate.")

(defvar *predicate-rule-index* (make-hash-table :test #'eq)
  "Secondary index.  Key: conclusion-predicate symbol.  Value: list of rule-id symbols.
   Used during backward-chaining queries (future extension).")

(defun clear-databases ()
  "Wipe all three databases and both indexes.  Useful between test runs.
   Does NOT reset the ID counter — IDs remain globally unique across resets."
  (clrhash *fact-db*)
  (clrhash *rule-db*)
  (clrhash *principle-db*)
  (clrhash *predicate-fact-index*)
  (clrhash *predicate-rule-index*)
  (values))


;;; ---------------------------------------------------------------------------
;;; Section 6 — Fact storage and retrieval
;;; ---------------------------------------------------------------------------

(defun store-fact (fact)
  "Add FACT to *FACT-DB* and update the predicate index.
   If an identical fact (same predicate and args) already exists, the duplicate
   is silently discarded and the existing fact is returned instead.
   Returns the stored FACT (possibly the pre-existing one)."
  (let ((existing (find-if (lambda (f)
                             (and (eq (fact-predicate f) (fact-predicate fact))
              (equal (fact-args f) (fact-args fact))
              (eq (fact-negative-p f) (fact-negative-p fact))))
            (lookup-facts :predicate (fact-predicate fact)
                :negative-p (fact-negative-p fact)))))
    (if existing
        ;; Duplicate — return what we already have rather than cluttering the DB.
        existing
        (progn
          ;; New fact — register it in the primary database.
          (setf (gethash (fact-id fact) *fact-db*) fact)
              ;; Update the predicate → [fact-id ...] index.
          (push (fact-id fact)
                (gethash (fact-predicate fact) *predicate-fact-index* nil))
          fact))))

(defun retract-fact (fact-id)
  "Remove the fact with FACT-ID from *FACT-DB* and clean up the predicate index.
   Returns T if the fact existed and was removed, NIL otherwise."
  (let ((fact (gethash fact-id *fact-db*)))
    (when fact
      ;; Remove from predicate index first.
      (setf (gethash (fact-predicate fact) *predicate-fact-index*)
            (remove fact-id
                    (gethash (fact-predicate fact) *predicate-fact-index*)
                    :test #'eq))
      ;; Remove from the primary database.
      (remhash fact-id *fact-db*)
      t)))

(defun lookup-facts (&key predicate (negative-p :any))
  "Return a list of FACT structs.
   If PREDICATE is supplied, only facts with that predicate are returned.
   If NEGATIVE-P is NIL or T, filter by fact polarity as well.
   If NEGATIVE-P is :ANY, return both positive and negative facts."
  (if predicate
      ;; Use the index for O(k) lookup instead of scanning all facts.
      (remove-if-not (lambda (fact)
           (or (eq negative-p :any)
         (eq (fact-negative-p fact) negative-p)))
         (mapcar (lambda (id) (gethash id *fact-db*))
           (gethash predicate *predicate-fact-index* nil)))
      ;; No filter — return everything.
      (loop for fact being the hash-values of *fact-db* collect fact)))

(defun all-facts ()
  "Return a list of all FACT structs currently in *FACT-DB*."
  (lookup-facts))

(defun fact-exists-p (predicate &rest args)
  "Return T if *FACT-DB* contains a fact with the given PREDICATE and ARGS."
  (not (null (find-if (lambda (f) (and (not (fact-negative-p f))
                                       (equal (fact-args f) args)))
                      (lookup-facts :predicate predicate :negative-p nil)))))

(defun touch-fact (fact-id)
  "Increment the usage counter and refresh the timestamp of the fact with FACT-ID.
   Called by the inference engine each time it reads a fact during matching.
   This data feeds the Memory Pruning layer's decay calculation."
  (let ((fact (gethash fact-id *fact-db*)))
    (when fact
      (incf (fact-usage-count fact))
      (setf (fact-last-accessed fact) (get-universal-time)))))


;;; ---------------------------------------------------------------------------
;;; Section 7 — Rule storage and retrieval
;;; ---------------------------------------------------------------------------

(defun store-rule (rule)
  "Add RULE to *RULE-DB* and update the conclusion-predicate index.
   Duplicate rules (same name) are silently overwritten — this allows
   the Macro Formation System to update rules in-place."
  (setf (gethash (rule-id rule) *rule-db*) rule)
  ;; Index by the conclusion predicate to support future backward chaining.
  (let ((conclusion-pred (first (rule-conclusion rule))))
    (push (rule-id rule)
          (gethash conclusion-pred *predicate-rule-index* nil)))
  rule)

(defun lookup-rules (&key predicate)
  "Return rules sorted by descending priority (highest-priority rules first).
   If PREDICATE is given, only rules whose conclusion head matches are returned."
  (let ((raw (if predicate
                 (mapcar (lambda (id) (gethash id *rule-db*))
                         (gethash predicate *predicate-rule-index* nil))
                 (loop for r being the hash-values of *rule-db* collect r))))
    ;; Sort so that high-priority rules (principles) fire before general rules.
    (sort (copy-list raw) #'> :key #'rule-priority)))

(defun all-rules ()
  "Return all rules sorted by descending priority."
  (lookup-rules))


;;; ---------------------------------------------------------------------------
;;; Section 8 — Principle storage and retrieval
;;; ---------------------------------------------------------------------------

(defun store-principle (principle)
  "Add PRINCIPLE to *PRINCIPLE-DB*.
   Also registers the underlying rule in *RULE-DB* with a very high priority
   so that it fires before ordinary rules — this is the payoff of promotion."
  (setf (gethash (principle-id principle) *principle-db*) principle)
  ;; Give the underlying rule max priority so it short-circuits inference.
  (setf (rule-priority (principle-rule principle)) 1000)
  (store-rule (principle-rule principle))
  principle)

(defun all-principles ()
  "Return a list of all PRINCIPLE structs, sorted by descending score."
  (sort (loop for p being the hash-values of *principle-db* collect p)
        #'> :key #'principle-score))

;;; =============================================================================
;;; Layer 3 — Truth Maintenance System (JTMS)
;;; File: src/truth-maintenance/tms.lisp
;;;
;;; Implements a Justification-Based Truth Maintenance System (JTMS) modelled
;;; after the original paper: Doyle, J. (1979) "A Truth Maintenance System".
;;;
;;; Core idea:
;;;   Every fact that the inference engine derives is not self-supporting.
;;;   Its belief depends on the facts that were used to derive it.  If one of
;;;   those "parent" facts is later retracted, the derived fact loses its
;;;   justification and must also be retracted — and so must any facts that
;;;   were derived from IT, and so on transitively.
;;;
;;; Data structure — JUSTIFICATION:
;;;   derived-id   — the fact ID of the fact whose existence is justified.
;;;   rule-id      — the rule that was fired to derive this fact.
;;;   parent-ids   — list of fact IDs whose truth supports this derivation.
;;;
;;; Dependency graph (separate from cl-graph Layer 5):
;;;   *JUSTIFICATION-TABLE*  maps  derived-fact-id → JUSTIFICATION
;;;   *DEPENDENTS-TABLE*     maps  parent-fact-id  → list of derived-fact-ids
;;;                          (the reverse direction, for O(1) cascade lookup)
;;;
;;; Contradiction handling:
;;;   A CONTRADICTION is registered as a pair of fact IDs that cannot both be
;;;   true simultaneously.  The check-contradictions function scans for such
;;;   pairs and retracts the most recently added fact from each conflicting pair.
;;; =============================================================================

(in-package :jarvis.truth-maintenance)


;;; ---------------------------------------------------------------------------
;;; Section 1 — Justification structure
;;; ---------------------------------------------------------------------------

(defstruct justification
  "Records why a fact is believed: which rule fired and which facts it needed."
  derived-id   ; symbol — the fact that was derived
  rule-id      ; symbol — the rule that produced it
  parent-ids)  ; list of symbols — facts that were consumed as conditions

(defvar *justification-table* (make-hash-table :test #'eq)
  "Maps derived-fact-id → JUSTIFICATION.
   Queried during retraction to find the support chain of any given fact.")

(defvar *dependents-table* (make-hash-table :test #'eq)
  "Maps parent-fact-id → list of derived-fact-ids that depend on it.
   This reverse index is what makes cascade retraction efficient:
   instead of scanning all justifications we jump straight to the children.")

(defvar *contradiction-pairs* nil
  "A list of (fact-id-A . fact-id-B) pairs registered via REGISTER-CONTRADICTION.
   CHECK-CONTRADICTIONS scans this list and resolves conflicts.")


;;; ---------------------------------------------------------------------------
;;; Section 2 — Adding justifications
;;;
;;; Called by the Inference Engine (via the *ON-RULE-FIRED* hook in practice,
;;; or directly after FIRE-RULE) each time a new derivation is made.
;;; ---------------------------------------------------------------------------

(defun add-justification (derived-id rule-id parent-ids)
  "Record that DERIVED-ID was derived by RULE-ID from the facts in PARENT-IDS.
   Updates both the forward table (derived → justification) and the
   reverse table (each parent → derived children list).
   Returns the new JUSTIFICATION struct."
  (let ((just (make-justification :derived-id derived-id
                                  :rule-id    rule-id
                                  :parent-ids parent-ids)))
    ;; Forward direction: this fact's justification.
    (setf (gethash derived-id *justification-table*) just)
    ;; Reverse direction: each parent gains this derived fact as a dependent.
    (dolist (pid parent-ids)
      (push derived-id (gethash pid *dependents-table* nil)))
    just))

(defun justification-for (fact-id)
  "Return the JUSTIFICATION for FACT-ID, or NIL if the fact was asserted
   directly (i.e., it is a root assumption with no derivation history)."
  (gethash fact-id *justification-table*))

(defun supported-p (fact-id)
  "Return T if FACT-ID has at least one recorded justification in this TMS.
   Facts asserted by the user with no derivation are considered 'always supported'
   (they are root assumptions) — return T for those as well."
  (or (not (jarvis.knowledge:fact-derived-p
            (gethash fact-id jarvis.knowledge:*fact-db*)))
      (not (null (gethash fact-id *justification-table*)))))


;;; ---------------------------------------------------------------------------
;;; Section 3 — Cascade retraction
;;;
;;; Retraction is propagated depth-first through *DEPENDENTS-TABLE*.
;;; We collect every fact that loses support and remove them all at once to
;;; avoid modifying the database mid-traversal.
;;; ---------------------------------------------------------------------------

(defun collect-unsupported (fact-id visited)
  "Recursively collect all fact-ids that would lose support if FACT-ID were
   removed.  VISITED is an EQ-hash-table used to prevent infinite loops in
   (theoretically impossible) circular dependency graphs.
   Returns a flat list of all affected IDs including FACT-ID itself."
  (unless (gethash fact-id visited)
    (setf (gethash fact-id visited) t)
    (cons fact-id
          (loop for dependent-id in (gethash fact-id *dependents-table* nil)
                ;; Only propagate to facts that are still in the database.
                when (gethash dependent-id jarvis.knowledge:*fact-db*)
                  append (collect-unsupported dependent-id visited)))))

(defun retract-with-support (fact-id)
  "Remove FACT-ID and every fact that transitively depended on it.
   Works by collecting the unsupported set first, then removing all of them.
   Returns a list of all retracted fact-ids (useful for logging / the TMS UI)."
  (let ((visited (make-hash-table :test #'eq)))
    (let ((to-remove (collect-unsupported fact-id visited)))
      (dolist (id to-remove)
        ;; Remove from the knowledge base.
        (jarvis.knowledge:retract-fact id)
        ;; Remove the justification record so memory stays tidy.
        (let ((just (gethash id *justification-table*)))
          (when just
            ;; Unlink from parents' dependents lists.
            (dolist (pid (justification-parent-ids just))
              (setf (gethash pid *dependents-table*)
                    (remove id (gethash pid *dependents-table* nil) :test #'eq)))
            (remhash id *justification-table*))))
      to-remove)))


;;; ---------------------------------------------------------------------------
;;; Section 4 — Dependency graph accessors
;;; ---------------------------------------------------------------------------

(defun dependency-parents (fact-id)
  "Return the list of fact-ids on which FACT-ID directly depends.
   Returns NIL for root assumptions (user-asserted facts)."
  (let ((just (justification-for fact-id)))
    (when just
      (justification-parent-ids just))))

(defun dependency-children (fact-id)
  "Return the list of fact-ids that directly depend on FACT-ID."
  (gethash fact-id *dependents-table* nil))


;;; ---------------------------------------------------------------------------
;;; Section 5 — Contradiction detection and resolution
;;; ---------------------------------------------------------------------------

(defun register-contradiction (fact-id-a fact-id-b)
  "Record that FACT-ID-A and FACT-ID-B cannot both be believed simultaneously.
   CHECK-CONTRADICTIONS will enforce this constraint by retracting one of them."
  (pushnew (cons fact-id-a fact-id-b) *contradiction-pairs*
           :test (lambda (a b)
                   (or (and (eq (car a) (car b)) (eq (cdr a) (cdr b)))
                       (and (eq (car a) (cdr b)) (eq (cdr a) (car b)))))))

(defun check-contradictions ()
  "Scan all registered contradiction pairs.  For any pair where BOTH facts
   are currently believed, retract the one that was derived most recently
   (i.e., the one with the higher fact-id number — a proxy for recency since
   IDs are assigned monotonically).
   Returns T if at least one contradiction was found and resolved, NIL otherwise."
  (let ((found nil))
    (dolist (pair *contradiction-pairs*)
      (let* ((id-a (car pair))
             (id-b (cdr pair))
             (fact-a (gethash id-a jarvis.knowledge:*fact-db*))
             (fact-b (gethash id-b jarvis.knowledge:*fact-db*)))
        ;; Both facts must still exist for a contradiction to be live.
        (when (and fact-a fact-b)
          (setf found t)
          (format t "[TMS] Contradiction detected between ~A and ~A~%" id-a id-b)
          ;; Retract the more recently derived one (higher numeric ID suffix).
          ;; This is a simple heuristic; a real system might use Doyle's
          ;; dependency-directed backtracking to choose more carefully.
          (let ((retract-id (if (string> (symbol-name id-a)
                                         (symbol-name id-b))
                                id-a
                                id-b)))
            (format t "[TMS] Retracting ~A and its dependents.~%" retract-id)
            (retract-with-support retract-id)))))
    found))


;;; ---------------------------------------------------------------------------
;;; Section 6 — TMS reset
;;;
;;; Called from the Meta Controller or test harness to wipe all TMS state
;;; between runs.  Must be called alongside JARVIS.KNOWLEDGE:CLEAR-DATABASES
;;; to ensure the full system starts from a clean slate.
;;; ---------------------------------------------------------------------------

(defun clear-tms ()
  "Wipe all TMS tables: justifications, dependents, and contradiction pairs.
   Call this together with JARVIS.KNOWLEDGE:CLEAR-DATABASES when resetting."
  (clrhash *justification-table*)
  (clrhash *dependents-table*)
  (setf *contradiction-pairs* nil)
  (values))

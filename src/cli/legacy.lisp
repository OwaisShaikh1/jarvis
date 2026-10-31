;;; =============================================================================
;;; Jarvis — Main Entry Point
;;; File: src/cli/legacy.lisp
;;;
;;; Wires the first five layers together into a single runnable demo.
;;; Each layer is exercised in the order described in architecture.md so you
;;; can verify the pipeline is working before you begin adding logic.
;;;
;;; Demonstration scenario — classic Socratic syllogism extended to two people:
;;;
;;;   User asserts:
;;;     human(socrates)
;;;     human(plato)
;;;
;;;   Rules loaded:
;;;     IF human(?x)   THEN mortal(?x)         [two-hop chain, step 1]
;;;     IF mortal(?x)  THEN finite-life(?x)    [two-hop chain, step 2]
;;;
;;;   Expected derivations (4 new facts):
;;;     mortal(socrates), mortal(plato)
;;;     finite-life(socrates), finite-life(plato)
;;;
;;;   TMS retraction demo:
;;;     After inference, retract human(socrates).
;;;     The TMS cascades: mortal(socrates) and finite-life(socrates) disappear.
;;;     human(plato) and its descendants remain untouched.
;;;
;;; How to run (from the project root):
;;;   sbcl --load "load-system.lisp" --load "main.lisp" --eval "(main)" --quit
;;;
;;; Or interactively from the REPL after (load "load-system.lisp"):
;;;   (load "main.lisp")
;;;   (main)
;;;
;;; Interactive CLI (after loading main.lisp):
;;;   (jarvis-cli)
;;; =============================================================================

(in-package :cl-user)


;;; ---------------------------------------------------------------------------
;;; Helper — horizontal separator for readable console output
;;; ---------------------------------------------------------------------------

(defun section (title)
  "Print a titled section header so each layer's output is easy to find."
  (format t "~%~%=== ~A ===~%" title))

;;; ---------------------------------------------------------------------------
;;; Helper — pretty-print a derivation graph
;;;
;;; Shows the full node and edge table of a DERIVATION-GRAPH so you can
;;; visualise the causal structure of one inference episode.
;;; ---------------------------------------------------------------------------

(declaim (ftype function register-opposite-polarity-contradictions))

(defun print-derivation-graph (dg)
  "Print the full node list and edge list of derivation graph DG."
  (format t "[graph] id=~A  nodes=~A  edges=~A  depth=~A~%"
          (jarvis.graph:derivation-graph-id dg)
          (hash-table-count (jarvis.graph:derivation-graph-node-table dg))
          (length           (jarvis.graph:derivation-graph-edges dg))
          (jarvis.graph:graph-depth dg))

  ;; ── Root nodes (user-asserted facts with no incoming edges) ──────────────
  (format t "  Root nodes (base assumptions):~%")
  (dolist (id (jarvis.graph:root-nodes dg))
    (let ((node (jarvis.graph:get-node dg id)))
      (format t "    [~4A] ~A~%"
              (jarvis.graph:graph-node-type  node)
              (jarvis.graph:graph-node-label node))))

  ;; ── Leaf nodes (deepest conclusions, no outgoing edges) ──────────────────
  (format t "  Leaf nodes (final conclusions):~%")
  (dolist (id (jarvis.graph:leaf-nodes dg))
    (let ((node (jarvis.graph:get-node dg id)))
      (format t "    [~4A] ~A~%"
              (jarvis.graph:graph-node-type  node)
              (jarvis.graph:graph-node-label node))))

  ;; ── Full edge list ────────────────────────────────────────────────────────
  (format t "  Edges (from → relation → to):~%")
  (dolist (edge (jarvis.graph:derivation-graph-edges dg))
    (let ((from-node (jarvis.graph:get-node dg (jarvis.graph:graph-edge-from-id edge)))
          (to-node   (jarvis.graph:get-node dg (jarvis.graph:graph-edge-to-id   edge))))
      (format t "    ~A  --[~A]-->  ~A~%"
              (jarvis.graph:graph-node-label from-node)
              (jarvis.graph:graph-edge-relation  edge)
              (jarvis.graph:graph-node-label to-node)))))


;;; ---------------------------------------------------------------------------
;;; MAIN — the full five-layer demonstration
;;;
;;; Call (main) to run the demo from scratch.  It is safe to call multiple
;;; times since RESET-ALL wipes all state at the beginning.
;;; ---------------------------------------------------------------------------

(defun legacy-main ()
  "Run the full five-layer demo from a clean state.
   Exercises every exported function in Layers 1–5 in the order prescribed
   by the architecture document."

  (format t "~%###############################################~%")
  (format t "##  JARVIS — Symbolic Reasoning Demo         ##~%")
  (format t "##  Layers 1-5  |  Socratic syllogism        ##~%")
  (format t "###############################################~%")


  ;;; ─────────────────────────────────────────────────────────────────────────
  ;;; Phase 0 — Reset all state
  ;;;
  ;;; Always start from a clean slate so repeated calls produce identical
  ;;; output.  We wipe the knowledge databases, TMS tables, and trace store.
  ;;; The ID counter is NOT reset so IDs are unique across all runs in a
  ;;; single process image.
  ;;; ─────────────────────────────────────────────────────────────────────────

  (section "Phase 0: Reset")
  (jarvis.knowledge:clear-databases)        ; wipe FACT-DB, RULE-DB, PRINCIPLE-DB
  (jarvis.truth-maintenance:clear-tms)      ; wipe justification + dependents tables
  (jarvis.trace:clear-traces)               ; wipe completed trace archive
  (format t "[reset] All databases cleared.~%")


  ;;; ─────────────────────────────────────────────────────────────────────────
  ;;; Phase 1 — Knowledge Representation (Layer 1)
  ;;;
  ;;; We construct FACT and RULE structs and commit them to the databases.
  ;;;
  ;;; Facts use only ground symbols (no variables).
  ;;; Rules use Prolog-style ?variables that the inference engine will bind
  ;;; to ground terms during condition matching.
  ;;;
  ;;; Rule pattern format:  (predicate  arg1  arg2  ...)
  ;;; A ?variable at any arg position will unify with any constant.
  ;;; ─────────────────────────────────────────────────────────────────────────

  (section "Phase 1: Knowledge Representation (Layer 1)")

  ;; Assert facts into *FACT-DB*.
  ;; STORE-FACT is idempotent: if an identical fact already exists it is
  ;; returned instead of creating a duplicate.
  (let ((f-soc (jarvis.knowledge:make-fact 'human 'socrates))
        (f-pla (jarvis.knowledge:make-fact 'human 'plato)))
    (jarvis.knowledge:store-fact f-soc)
    (jarvis.knowledge:store-fact f-pla)
    (format t "[KB] Asserted: human(socrates)  id=~A~%"
            (jarvis.knowledge:fact-id f-soc))
    (format t "[KB] Asserted: human(plato)     id=~A~%"
            (jarvis.knowledge:fact-id f-pla)))

  ;; Define rule 1: IF human(?x) THEN mortal(?x)
  ;; This derives mortality directly from humanity — one hop.
  (let ((r1 (jarvis.knowledge:make-rule
             'human-implies-mortal     ; human-readable name for traces & logs
             '((human ?x))             ; one condition pattern
             '(mortal ?x))))           ; conclusion pattern
    (jarvis.knowledge:store-rule r1)
    (format t "[KB] Rule ~A: ~A  =>  ~A~%"
            (jarvis.knowledge:rule-id r1)
            (jarvis.knowledge:rule-conditions r1)
            (jarvis.knowledge:rule-conclusion  r1)))

  ;; Define rule 2: IF mortal(?x) THEN finite-life(?x)
  ;; This chains from rule 1 to create a two-hop derivation:
  ;;   human → mortal → finite-life
  (let ((r2 (jarvis.knowledge:make-rule
             'mortal-implies-finite-life
             '((mortal ?x))
             '(finite-life ?x))))
    (jarvis.knowledge:store-rule r2)
    (format t "[KB] Rule ~A: ~A  =>  ~A~%"
            (jarvis.knowledge:rule-id r2)
            (jarvis.knowledge:rule-conditions r2)
            (jarvis.knowledge:rule-conclusion  r2)))

  (format t "[KB] Databases: ~A facts, ~A rules.~%"
          (length (jarvis.knowledge:all-facts))
          (length (jarvis.knowledge:all-rules)))


  ;;; ─────────────────────────────────────────────────────────────────────────
  ;;; Phase 2 — Inference Engine (Layer 2)
  ;;;
  ;;; Before starting inference we open a trace session (Layer 4).  The trace
  ;;; recorder installs itself into *ON-RULE-FIRED* so it captures every step
  ;;; automatically while inference runs.  We close the session afterwards.
  ;;;
  ;;; RUN-INFERENCE:
  ;;;   • Builds an AGENDA of (rule . bindings) pairs by matching all rules
  ;;;     against the current *FACT-DB*.
  ;;;   • Pops and fires entries in descending priority order.
  ;;;   • Repeats until the agenda is empty or MAX-CYCLES is hit.
  ;;;   • Returns a deduplicated list of all newly derived FACTs.
  ;;; ─────────────────────────────────────────────────────────────────────────

  (section "Phase 2: Inference Engine (Layer 2)")

  ;; Open trace BEFORE inference so the hook is installed in time.
  (let ((session-id (jarvis.trace:begin-trace-session)))

    (let ((derived (jarvis.inference:run-inference)))

      (format t "[inference] Derived ~A new fact(s):~%" (length derived))
      (dolist (f derived)
        (format t "  ~A  (~A  ~{~A~^ ~})  derived=T~%"
                (jarvis.knowledge:fact-id       f)
                (jarvis.knowledge:fact-predicate f)
                (jarvis.knowledge:fact-args      f)))


    ;;; ───────────────────────────────────────────────────────────────────────
    ;;; Phase 3 — Truth Maintenance System (Layer 3)
    ;;;
    ;;; After inference we register a JUSTIFICATION for every derived fact.
    ;;; A justification records:
    ;;;   derived-fact-id ← rule-id ← list-of-parent-fact-ids
    ;;;
    ;;; We source the justifications from the trace steps (not from the
    ;;; inference engine directly) because the trace already contains the
    ;;; precise parent IDs thanks to the fixed INPUTS-FROM-BINDINGS function.
    ;;;
    ;;; Once justifications are in place, RETRACT-WITH-SUPPORT will correctly
    ;;; cascade any retraction down the dependency graph.
    ;;; ───────────────────────────────────────────────────────────────────────

    ;; Close the trace session to get the completed REASONING-TRACE struct.
    (let ((completed-trace (jarvis.trace:end-trace-session session-id)))

      (section "Phase 3: Truth Maintenance System (Layer 3) — Recording justifications")

      ;; Walk every recorded step and register its justification in the TMS.
      ;; This wires up the dependency graph that powers cascade retraction.
      (dolist (step (jarvis.trace:trace-steps completed-trace))
        (let ((out-id    (jarvis.trace:trace-step-output-id step))
              (rule-id   (jarvis.trace:trace-step-rule-id   step))
              (parent-ids (jarvis.trace:trace-step-input-ids step)))
          (jarvis.truth-maintenance:add-justification out-id rule-id parent-ids)
          (format t "[TMS] Justified ~A  ←  rule-~A  ←  ~A~%"
                  out-id rule-id parent-ids)))

        (register-opposite-polarity-contradictions)
        (jarvis.truth-maintenance:check-contradictions)


      ;;; ─────────────────────────────────────────────────────────────────────
      ;;; Phase 4 — Trace Recorder (Layer 4)
      ;;;
      ;;; Replay the completed trace in human-readable form.  Each TRACE-STEP
      ;;; shows which rule fired, which facts supplied the conditions, which
      ;;; fact was produced, and at what derivation depth.
      ;;;
      ;;; This is the data the Abstraction Engine (Layer 6) will mine for
      ;;; repeated subgraph patterns once you implement it.
      ;;; ─────────────────────────────────────────────────────────────────────

      (section "Phase 4: Trace Recorder (Layer 4) — Replay")
      (format t "[trace] Session:        ~A~%"
              (jarvis.trace:trace-session-id completed-trace))
      (format t "[trace] Start-state:    ~A fact(s)~%"
              (length (jarvis.trace:trace-start-state completed-trace)))
      (format t "[trace] End-state:      ~A fact(s)~%"
              (length (jarvis.trace:trace-end-state completed-trace)))
      (format t "[trace] Steps recorded: ~A  |  Max depth: ~A~%"
              (jarvis.trace:trace-step-count completed-trace)
              (jarvis.trace:trace-depth      completed-trace))
      (format t "~%  Step-by-step derivation:~%")
      (loop for step in (jarvis.trace:trace-steps completed-trace)
            for n from 1
            do (format t "  [~A] Rule ~A  inputs=~A  output=~A  depth=~A~%"
                       n
                       (jarvis.trace:trace-step-rule-id   step)
                       (jarvis.trace:trace-step-input-ids step)
                       (jarvis.trace:trace-step-output-id step)
                       (jarvis.trace:trace-step-depth     step)))


      ;;; ─────────────────────────────────────────────────────────────────────
      ;;; Phase 5 — Graph Representation (Layer 5)
      ;;;
      ;;; Convert the completed trace into a Directed Acyclic Graph.
      ;;; TRACE->GRAPH walks the trace steps and builds:
      ;;;   • One :fact node per distinct fact involved.
      ;;;   • One :rule node per rule that fired (even if it fired for
      ;;;     multiple individuals — each firing is a separate node).
      ;;;   • :input-of edges  — fact contributed to a rule condition.
      ;;;   • :produces  edges — rule produced a fact.
      ;;;
      ;;; The result is stored in a DERIVATION-GRAPH struct.  The Abstraction
      ;;; Engine will later feed pairs of these graphs into COMMON-SUBGRAPH
      ;;; to discover recurring reasoning templates.
      ;;; ─────────────────────────────────────────────────────────────────────

      (section "Phase 5: Graph Representation (Layer 5)")
      (let ((dg (jarvis.graph:trace->graph completed-trace)))
        (print-derivation-graph dg))


      ;;; ─────────────────────────────────────────────────────────────────────
      ;;; Phase 3 (continued) — TMS retraction cascade demonstration
      ;;;
      ;;; Now we show cascade retraction.  We retract the ground fact
      ;;; human(socrates).  Because we registered justifications above:
      ;;;
      ;;;   mortal(socrates)      justified by rule + human(socrates)
      ;;;   finite-life(socrates) justified by rule + mortal(socrates)
      ;;;
      ;;; RETRACT-WITH-SUPPORT will remove human(socrates) from *FACT-DB*
      ;;; and then cascade to mortal(socrates) and finite-life(socrates).
      ;;; human(plato) and its two descendants are completely unaffected.
      ;;; ─────────────────────────────────────────────────────────────────────

      (section "Phase 3 (continued): TMS Retraction Cascade")

      (let* ((all-before (jarvis.knowledge:all-facts))
             ;; Find the fact whose predicate is HUMAN and whose single arg is SOCRATES.
             (soc-human  (find-if (lambda (f)
                                    (and (eq 'human
                                             (jarvis.knowledge:fact-predicate f))
                                         (equal '(socrates)
                                                (jarvis.knowledge:fact-args f))))
                                  all-before)))
        (format t "[TMS] Facts before retraction: ~A~%" (length all-before))
        (if soc-human
            (progn
              (format t "[TMS] Retracting ~A (human(socrates))...~%"
                      (jarvis.knowledge:fact-id soc-human))
              ;; RETRACT-WITH-SUPPORT removes the named fact and recursively
              ;; retracts any fact whose only support chain ran through it.
              (jarvis.truth-maintenance:retract-with-support
               (jarvis.knowledge:fact-id soc-human))
              (let ((after (jarvis.knowledge:all-facts)))
                (format t "[TMS] Facts after  retraction: ~A~%" (length after))
                (format t "[TMS] Remaining facts:~%")
                (dolist (f after)
                  (format t "  ~A  ~A(~{~A~^ ~})~%"
                          (jarvis.knowledge:fact-id       f)
                          (jarvis.knowledge:fact-predicate f)
                          (jarvis.knowledge:fact-args      f)))))
            (format t "[TMS] human(socrates) not found — skipping.~%")))


      ;;; ─────────────────────────────────────────────────────────────────────
      ;;; Summary
      ;;; ─────────────────────────────────────────────────────────────────────

      (section "Summary")
      (format t "  Facts remaining in DB : ~A~%"
              (length (jarvis.knowledge:all-facts)))
      (format t "  Rules in DB           : ~A~%"
              (length (jarvis.knowledge:all-rules)))
      (format t "  Completed traces      : ~A~%"
              (length (jarvis.trace:all-traces)))
      (format t "~%Next layers to implement:~%")
      (format t "  Layer 6  — Abstraction Engine  (common-subgraph mining)~%")
      (format t "  Layer 7  — Macro Formation     (pattern compression)~%")
      (format t "  Layer 8  — Principle Optimiser (score + weight rules)~%")
      (format t "  Layer 9  — Memory Pruning      (LRU + importance decay)~%")
      (format t "  Layer 10 — Meta-Controller     (goal selection + reflection)~%")
                        (format t "~%")))))


;;; ---------------------------------------------------------------------------
;;; CLI helpers
;;; ---------------------------------------------------------------------------

(defvar *data-dir* (asdf:system-relative-pathname :jarvis "data/"))
(defvar *persistence-loaded-p* nil)

(defun facts-file ()
        "Return the absolute path of the persisted facts file."
        (merge-pathnames "facts.txt" *data-dir*))

(defun rules-file ()
        "Return the absolute path of the persisted rules file."
        (merge-pathnames "rules.txt" *data-dir*))

(defun ensure-persistence-paths ()
        "Ensure the persistence directory exists before reading/writing files."
        (ensure-directories-exist (facts-file))
        (ensure-directories-exist (rules-file))
        (values))

(defun fact->record (fact)
        "Serialize FACT into a readable plist record."
        (list :predicate (jarvis.knowledge:fact-predicate fact)
                  :args (jarvis.knowledge:fact-args fact)
                  :negative (jarvis.knowledge:fact-negative-p fact)
                  :derived (jarvis.knowledge:fact-derived-p fact)))

(defun record->fact (record)
        "Deserialize RECORD into a FACT struct."
        (let* ((predicate (getf record :predicate))
                         (args      (getf record :args))
                         (negative  (and (getf record :negative) t))
                         (derived   (and (getf record :derived) t))
                         (fact      (apply #'jarvis.knowledge:make-fact predicate args)))
                (setf (jarvis.knowledge:fact-negative-p fact) negative)
                (setf (jarvis.knowledge:fact-derived-p  fact) derived)
                fact))

(defun rule->record (rule)
        "Serialize RULE into a readable plist record."
        (list :name (jarvis.knowledge:rule-name rule)
                  :conditions (jarvis.knowledge:rule-conditions rule)
                  :conclusion (jarvis.knowledge:rule-conclusion rule)
                  :negative (jarvis.knowledge:rule-negative-p rule)
                  :priority (jarvis.knowledge:rule-priority rule)))

(defun same-rule-signature-p (rule name conditions conclusion negative)
        "Return T if RULE has the same logical content as the provided fields."
        (and (eq (jarvis.knowledge:rule-name rule) name)
                 (equal (jarvis.knowledge:rule-conditions rule) conditions)
                 (equal (jarvis.knowledge:rule-conclusion rule) conclusion)
                 (eq (jarvis.knowledge:rule-negative-p rule) negative)))

(defun record->rule (record)
        "Deserialize RECORD into a RULE struct."
        (let* ((name       (getf record :name))
                         (conditions (getf record :conditions))
                         (conclusion (getf record :conclusion))
                         (negative   (and (getf record :negative) t))
                         (priority   (or (getf record :priority) 0))
                         (encoded-conclusion (if negative
                                                                     (cons '! conclusion)
                                                                     conclusion))
                         (rule (jarvis.knowledge:make-rule name conditions encoded-conclusion)))
                (setf (jarvis.knowledge:rule-priority rule) priority)
                rule))

(defun load-rule-record (record)
        "Load RECORD unless it violates the rule validation constraints."
        (handler-case
                (let* ((rule (record->rule record))
                       (exists (find-if (lambda (r)
                                          (same-rule-signature-p
                                           r
                                           (jarvis.knowledge:rule-name rule)
                                           (jarvis.knowledge:rule-conditions rule)
                                           (jarvis.knowledge:rule-conclusion rule)
                                           (jarvis.knowledge:rule-negative-p rule)))
                                        (jarvis.knowledge:all-rules))))
                  (unless exists
                    (jarvis.knowledge:store-rule rule)))
          (jarvis.knowledge:rule-error (err)
            (format t "[persistence] Skipping invalid rule: ~A~%"
                    (jarvis.knowledge:rule-error-message err)))))

(defun save-persistent-state ()
        "Persist all current facts and rules to separate txt files."
        (ensure-persistence-paths)
        (let ((*read-default-float-format* 'double-float))
          (with-open-file (out (facts-file)
                                                   :direction :output
                                                   :if-exists :supersede
                                                   :if-does-not-exist :create)
                  (dolist (fact (jarvis.knowledge:all-facts))
                    (unless (jarvis.knowledge:fact-derived-p fact)
                      (prin1 (fact->record fact) out)
                      (terpri out))))
          (with-open-file (out (rules-file)
                                                   :direction :output
                                                   :if-exists :supersede
                                                   :if-does-not-exist :create)
                  (dolist (rule (jarvis.knowledge:all-rules))
                          (prin1 (rule->record rule) out)
                          (terpri out))))
        (values))

(defun load-persistent-state ()
        "Load facts and rules from persistence files once per process." 
        (unless *persistence-loaded-p*
                (ensure-persistence-paths)
                (when (probe-file (facts-file))
                        (with-open-file (in (facts-file) :direction :input)
                                (let ((*read-eval* nil)
                                      ;; Persisted records are interpreted as CL-USER data.
                                      (*package* (find-package :cl-user))
                                      (*read-default-float-format* 'double-float))
                                  (loop for record = (read in nil :eof)
                                            until (eq record :eof)
                                            do (unless (getf record :derived)
                                                 (jarvis.knowledge:store-fact
                                                  (record->fact record)))))))
                (when (probe-file (rules-file))
                        (with-open-file (in (rules-file) :direction :input)
                                (let ((*read-eval* nil)
                                      ;; Persisted records are interpreted as CL-USER data.
                                      (*package* (find-package :cl-user))
                                      (*read-default-float-format* 'double-float))
                                  (loop for record = (read in nil :eof)
                                            until (eq record :eof)
                                            do (load-rule-record record)))))
                (setf *persistence-loaded-p* t)
                (jarvis.engine:infer :quiet t))
        (values))

(defun ws-char-p (ch)
        "Return T when CH is considered command-line whitespace."
        (or (char= ch #\Space)
                        (char= ch #\Tab)))

(defun split-whitespace (line)
        "Split LINE by spaces/tabs and return a list of non-empty tokens."
        (let ((tokens nil)
                                (len (length line))
                                (start 0))
                (labels ((emit-token (a b)
                                                         (when (< a b)
                                                                 (push (subseq line a b) tokens))))
                        (loop while (< start len) do
                                ;; Skip leading whitespace.
                                (loop while (and (< start len)
                                                                                                 (ws-char-p (char line start)))
                                                        do (incf start))
                                (let ((end start))
                                        ;; Scan token until next whitespace.
                                        (loop while (and (< end len)
                                                                                                         (not (ws-char-p (char line end))))
                                                                do (incf end))
                                        (emit-token start end)
                                        (setf start end))))
                (nreverse tokens)))

(defun command-rest (line)
        "Return trimmed text after the first command token in LINE."
        (let* ((len (length line))
                                 (i 0))
                (loop while (and (< i len) (ws-char-p (char line i))) do (incf i))
                (loop while (and (< i len) (not (ws-char-p (char line i)))) do (incf i))
                (loop while (and (< i len) (ws-char-p (char line i))) do (incf i))
                (if (< i len)
                                (string-trim '(#\Space #\Tab) (subseq line i))
                                "")))

(defun id-symbol< (a b)
        "Sort helper for symbol IDs like FACT-12."
        (string< (symbol-name a) (symbol-name b)))

(defun normalize-fact-id-token (token)
        "Convert TOKEN to an internal FACT id symbol (accepts FACT1, FACT-1, or 1)."
        (let* ((trim (string-trim '(#\Space #\Tab) token))
                                 (up   (string-upcase trim)))
                (cond
                        ((string= up "")
                         nil)
                        ((every #'digit-char-p up)
                         (intern (format nil "FACT-~A" up) :jarvis.knowledge))
                        ((and (>= (length up) 5)
                                                (string= (subseq up 0 5) "FACT-")
                                                (every #'digit-char-p (subseq up 5)))
                         (intern up :jarvis.knowledge))
                        ((and (>= (length up) 5)
                                                (string= (subseq up 0 5) "FACT#")
                                                (every #'digit-char-p (subseq up 5)))
                         (intern (format nil "FACT-~A" (subseq up 5)) :jarvis.knowledge))
                        ((and (>= (length up) 4)
                                                (string= (subseq up 0 4) "FACT")
                                                (every #'digit-char-p (subseq up 4)))
                         (intern (format nil "FACT-~A" (subseq up 4)) :jarvis.knowledge))
                        (t
                         nil))))

(defun lookup-fact-by-id (fact-id)
        "Return FACT struct for FACT-ID, or NIL."
        (gethash fact-id jarvis.knowledge::*fact-db*))

(defun parse-fact-token (token)
        "Resolve TOKEN to (values fact-id fact)."
        (let ((fid (normalize-fact-id-token token)))
                (values fid (and fid (lookup-fact-by-id fid)))))

(defun print-fact-brief (fact)
        "Print one line for FACT."
        (format t "  ~A  ~:[~;!~]~A(~{~A~^ ~})~@[  derived=T~]~%"
                                        (jarvis.knowledge:fact-id fact)
                                        (jarvis.knowledge:fact-negative-p fact)
                                        (jarvis.knowledge:fact-predicate fact)
                                        (jarvis.knowledge:fact-args fact)
                                        (and (jarvis.knowledge:fact-derived-p fact) t)))

(defun print-parent-summary (parent-ids)
        "Print a short list of parent facts by id and proposition."
        (dolist (pid parent-ids)
                (let ((pf (lookup-fact-by-id pid)))
                        (if pf
                                        (format t "    ~A: ~A(~{~A~^ ~})~%"
                                                                        pid
                                                                        (jarvis.knowledge:fact-predicate pf)
                                                                        (jarvis.knowledge:fact-args pf))
                                        (format t "    ~A: [retracted]~%" pid)))))

(defun fact-expression-string (fact)
        "Return canonical predicate(args...) text for FACT."
        (if fact
                        (format nil "~:[~;!~]~A(~{~A~^ ~})"
                                        (jarvis.knowledge:fact-negative-p fact)
                                        (jarvis.knowledge:fact-predicate fact)
                                        (jarvis.knowledge:fact-args fact))
                        "[missing-fact]"))

(defun rule-conclusion-expression-string (rule)
        "Return a printable rule conclusion including negation if present."
        (format nil "~:[~;!~]~A(~{~A~^ ~})"
                        (jarvis.knowledge:rule-negative-p rule)
                        (first (jarvis.knowledge:rule-conclusion rule))
                        (rest (jarvis.knowledge:rule-conclusion rule))))

(defun register-opposite-polarity-contradictions ()
        "Register contradiction pairs for facts that differ only by polarity."
        (let ((facts (jarvis.knowledge:all-facts)))
                (dolist (positive facts)
                        (unless (jarvis.knowledge:fact-negative-p positive)
                                (dolist (negative facts)
                                        (when (and (jarvis.knowledge:fact-negative-p negative)
                                                                 (eq (jarvis.knowledge:fact-predicate positive)
                                                                     (jarvis.knowledge:fact-predicate negative))
                                                                 (jarvis.knowledge:args-equal
                                                                  (jarvis.knowledge:fact-args positive)
                                                                  (jarvis.knowledge:fact-args negative)))
                                                (jarvis.truth-maintenance:register-contradiction
                                                 (jarvis.knowledge:fact-id positive)
                                                 (jarvis.knowledge:fact-id negative))))))))

(defun explain-why-immediate (fact-id)
        "Explain the immediate support for FACT-ID from the TMS." 
        (let* ((fact (lookup-fact-by-id fact-id))
                                 (just (jarvis.truth-maintenance:justification-for fact-id)))
                (cond
                        ((null fact)
                         (format t "[why] ~A is not currently in the fact database.~%" fact-id))
                        ((null just)
                         (format t "[why] ~A is a root assumption (user-asserted or no recorded justification).~%"
                                                         fact-id)
                         (print-fact-brief fact))
                        (t
                         (format t "[why] Immediate support for ~A:~%" fact-id)
                         (print-fact-brief fact)
                         (format t "  Derived via rule ~A from parent facts: ~A~%"
                                                         (jarvis.truth-maintenance::justification-rule-id just)
                                                         (jarvis.truth-maintenance::justification-parent-ids just))
                         (print-parent-summary (jarvis.truth-maintenance::justification-parent-ids just))))))

(defun explain-why-recursive (fact-id &optional (depth 0) (visited (make-hash-table :test #'eq)))
        "Print full support chain for FACT-ID back to root assumptions."
        (let* ((indent (make-string (* 4 depth) :initial-element #\Space))
                                 (fact   (lookup-fact-by-id fact-id))
                                 (just   (jarvis.truth-maintenance:justification-for fact-id)))
                (cond
                        ((null fact)
                         (format t "~A+ ~A  [retracted or missing]~%" indent fact-id))
                        ((gethash fact-id visited)
                         (format t "~A+ ~A  [already shown]~%" indent fact-id))
                        (t
                         (setf (gethash fact-id visited) t)
                         (format t "~A+ ~A  ~A~%"
                                                         indent
                                                         fact-id
                                                         (fact-expression-string fact))
                         (if just
                                         (progn
                                                 (format t "~A  because ~A from ~A~%"
                                                                                 indent
                                                                                 (jarvis.truth-maintenance::justification-rule-id just)
                                                                                 (jarvis.truth-maintenance::justification-parent-ids just))
                                                 (dolist (pid (jarvis.truth-maintenance::justification-parent-ids just))
                                                         (explain-why-recursive pid (1+ depth) visited)))
                                         (format t "~A  assumption (root)~%" indent))))))

(defun collect-proof-order (fact-id visited)
        "Return a parent-first list of fact IDs needed to prove FACT-ID."
        (if (gethash fact-id visited)
                        nil
                        (progn
                                (setf (gethash fact-id visited) t)
                                (let ((just (jarvis.truth-maintenance:justification-for fact-id)))
                                        (append
                                         (loop for pid in (if just
                                                                                   (jarvis.truth-maintenance::justification-parent-ids just)
                                                                                   nil)
                                                       append (collect-proof-order pid visited))
                                         (list fact-id))))))

(defun explain-proof-forward (fact-id)
        "Print a root-to-goal mathematical-style proof for FACT-ID."
        (let ((target (lookup-fact-by-id fact-id)))
                (if (null target)
                                (format t "[prove] ~A is not currently in the fact database.~%" fact-id)
                                (let* ((order (collect-proof-order fact-id (make-hash-table :test #'eq)))
                                                 (line-map (make-hash-table :test #'eq))
                                                 (line-no 0))
                                        (format t "[prove] Root-to-goal proof for ~A~%" fact-id)
                                        (format t "[prove] ----------------------------------------~%")
                                        (dolist (fid order)
                                                (incf line-no)
                                                (setf (gethash fid line-map) line-no)
                                                (let* ((fact (lookup-fact-by-id fid))
                                                                 (just (jarvis.truth-maintenance:justification-for fid))
                                                                 (expr (fact-expression-string fact)))
                                                        (if just
                                                                        (let* ((parent-ids (jarvis.truth-maintenance::justification-parent-ids just))
                                                                                         (parent-lines
                                                                                          (remove nil
                                                                                                          (mapcar (lambda (pid)
                                                                                                                            (gethash pid line-map))
                                                                                                                          parent-ids))))
                                                                                (format t "  ~2D. ~A   [~A]~%"
                                                                                                line-no expr fid)
                                                                                (format t "      from line~A ~{~A~^, ~} by ~A~%"
                                                                                                (if (= (length parent-lines) 1) "" "s")
                                                                                                parent-lines
                                                                                                (jarvis.truth-maintenance::justification-rule-id just)))
                                                                        (progn
                                                                                (format t "  ~2D. ~A   [~A]~%" line-no expr fid)
                                                                                (format t "      assumption~%")))))
                                        (format t "[prove] QED: ~A~%" (fact-expression-string target))))))

(defun list-facts-command ()
        "List currently believed facts." 
        (let ((facts (sort (copy-list (jarvis.knowledge:all-facts))
                                                                                 #'id-symbol<
                                                                                 :key #'jarvis.knowledge:fact-id)))
                (format t "[facts] ~A fact(s):~%" (length facts))
                (dolist (f facts)
                        (print-fact-brief f))))

(defun list-rules-command ()
        "List currently loaded rules." 
        (let ((rules (jarvis.knowledge:all-rules)))
                (format t "[rules] ~A rule(s):~%" (length rules))
                (dolist (r rules)
                        (format t "  ~A  ~A  if ~A  =>  ~A  priority=~A~@[  negative~]~%"
                                                        (jarvis.knowledge:rule-id r)
                                                        (jarvis.knowledge:rule-name r)
                                                        (jarvis.knowledge:rule-conditions r)
                                                        (rule-conclusion-expression-string r)
                                                        (jarvis.knowledge:rule-priority r)
                                                        (and (jarvis.knowledge:rule-negative-p r) t)))))

(defun run-inference-with-trace-and-tms (&key (max-cycles 1000))
        "Run inference, record trace, and add TMS justifications for new steps."
        (multiple-value-bind (derived completed-trace)
            (jarvis.engine:infer :max-cycles max-cycles)
          (register-opposite-polarity-contradictions)
          (jarvis.truth-maintenance:check-contradictions)
          (format t "[infer] Derived ~A new fact(s). Trace steps this session: ~A~%"
                  (length derived)
                  (jarvis.trace:trace-step-count completed-trace))
          (save-persistent-state)
          derived))

(defun print-cli-help ()
        "Print all available CLI commands." 
        (format t "~%Jarvis CLI commands:~%")
        (format t "  help | commands                    Show this command list.~%")
        (format t "  demo                               Run the full main demo pipeline.~%")
        (format t "  status                             Show fact/rule/trace counts.~%")
        (format t "  add-fact (predicate args...)       Assert one fact into the KB.~%")
        (format t "  add-rule <name> ((conds)) (conc)   Add one production rule.~%")
        (format t "  facts                              List all current facts.~%")
        (format t "  rules                              List all loaded rules.~%")
        (format t "  infer [max-cycles]                 Run inference + trace + TMS update.~%")
        (format t "  why <fact-id>                      Show immediate justification only.~%")
        (format t "  wy <fact-id> -r                    Show full recursive support chain.~%")
        (format t "  why <fact-id> -p                   Show root-to-goal proof (math style).~%")
        (format t "  prove <fact-id>                    Alias for proof-style explanation.~%")
        (format t "  why <fact-id> -r                   Alias of recursive explanation.~%")
        (format t "  retract <fact-id>                  Retract fact and all dependents.~%")
        (format t "  Negative rule syntax: (! dead ?x) or (!dead ?x)~%")
        (format t "  reset                              Clear KB + TMS + traces.~%")
        (format t "  quit | exit                        Leave CLI.~%")
        (format t "~%Fact id forms accepted: FACT-1, fact1, fact#1, or just 1.~%")
        (format t "Add syntax examples:~%")
        (format t "  add-fact (human plato)~%")
        (format t "  add-fact (!mortal harsh)~%")
        (format t "  add-rule human-implies-mortal ((human ?x)) (mortal ?x)~%")
        (format t "  add-rule alive-implies-not-dead ((alive ?x)) (! dead ?x)~%"))

(defun handle-why-command (tokens)
        "Handle why/wy commands." 
        (if (< (length tokens) 2)
                        (format t "[why] Usage: why <fact-id> [-r|-p]~%")
                        (multiple-value-bind (fid fact)
                                        (parse-fact-token (second tokens))
                                (cond
                                        ((null fid)
                                         (format t "[why] Could not parse fact id: ~A~%" (second tokens)))
                                        ((null fact)
                                         (format t "[why] Fact ~A is not currently in the database.~%" fid))
                                        ((or (find "-r" tokens :test #'string-equal)
                                                         (find "--recursive" tokens :test #'string-equal))
                                         (format t "[why] Recursive support chain for ~A:~%" fid)
                                         (explain-why-recursive fid))
                                        ((or (find "-p" tokens :test #'string-equal)
                                                         (find "--proof" tokens :test #'string-equal)
                                                         (find "--forward" tokens :test #'string-equal))
                                         (explain-proof-forward fid))
                                        (t
                                         (explain-why-immediate fid))))))

(defun parse-nonnegative-int (token)
        "Parse TOKEN as a non-negative integer, returning NIL on failure."
        (handler-case
                        (let ((n (parse-integer token :junk-allowed nil)))
                                (when (>= n 0) n))
                (error () nil)))

(defun parse-one-form (text &optional (start 0))
        "Read one Lisp form from TEXT at START, returning (values form next-pos err)."
        (handler-case
                        (let ((*read-eval* nil)
                              ;; User input and persisted data use CL-USER symbols.
                              (*package* (find-package :cl-user))
                              (*read-default-float-format* 'double-float))
                          (multiple-value-bind (form next-pos)
                                          (read-from-string text nil :eof :start start)
                                  (values form next-pos nil)))
                (error (e)
                        (values nil start e))))

(defun valid-pattern-p (pattern)
        "Return T when PATTERN has the shape (predicate arg1 ...)."
        (and (consp pattern)
                 (symbolp (first pattern))))

(defun valid-conditions-p (conditions)
        "Return T when CONDITIONS is a list of valid patterns."
        (and (listp conditions)
                 (every #'valid-pattern-p conditions)))

(defun normalize-fact-pattern (pattern)
        "Normalize fact PATTERN and return (values predicate args negative-p err-msg).
Supports (predicate ...), (! predicate ...), (not predicate ...), and (!predicate ...)."
        (cond
                ((not (consp pattern))
                 (values nil nil nil "Fact must be a list pattern."))
                ((string= (symbol-name (first pattern)) "!")
                 (if (and (second pattern) (symbolp (second pattern)))
                                 (values (second pattern) (cddr pattern) t nil)
                                 (values nil nil nil "Negative fact form (! ...) requires a predicate symbol.")))
                ((string= (symbol-name (first pattern)) "NOT")
                 (if (and (second pattern) (symbolp (second pattern)))
                                 (values (second pattern) (cddr pattern) t nil)
                                 (values nil nil nil "Negative fact form (not ...) requires a predicate symbol.")))
                ((and (symbolp (first pattern))
                            (> (length (symbol-name (first pattern))) 1)
                            (char= (char (symbol-name (first pattern)) 0) #\!))
                 (values (intern (subseq (symbol-name (first pattern)) 1)
                                                 (or (symbol-package (first pattern)) *package*))
                                 (rest pattern)
                                 t
                                 nil))
                ((and (symbolp (first pattern))
                            (char= (char (symbol-name (first pattern)) 0) #\!))
                 (values nil nil nil "Negative fact shorthand must be !predicate, not bare !."))
                ((symbolp (first pattern))
                 (values (first pattern) (rest pattern) nil nil))
                (t
                 (values nil nil nil "Fact predicate must be a symbol."))))

(defun valid-rule-conclusion-p (conclusion)
        "Return T when CONCLUSION is a valid positive pattern or a negative form."
        (and (consp conclusion)
                 (or (valid-pattern-p conclusion)
                         (and (or (string= (symbol-name (first conclusion)) "!")
                                  (string= (symbol-name (first conclusion)) "NOT")
                                  (and (symbolp (first conclusion))
                                           (let ((name (symbol-name (first conclusion))))
                                                 (and (> (length name) 0)
                                                          (char= (char name 0) #\!)))))))))

(defun handle-add-fact-command (line)
        "Handle: add-fact <fact-pattern>, where pattern is a Lisp form like (human plato)."
        (let ((rest (command-rest line)))
                (if (string= rest "")
                                (format t "[add-fact] Usage: add-fact (predicate arg1 arg2 ...)~%")
                                (multiple-value-bind (form pos err)
                                                (parse-one-form rest)
                                        (cond
                                                (err
                                                 (format t "[add-fact] Parse error: ~A~%" err))
                                                ((eq form :eof)
                                                 (format t "[add-fact] Missing fact pattern. Example: add-fact (human plato)~%"))
                                                ((not (string= (string-trim '(#\Space #\Tab) (subseq rest pos)) ""))
                                                 (format t "[add-fact] Unexpected trailing input after fact pattern.~%"))
                                                (t
                                                 (multiple-value-bind (predicate args negative-p fact-err)
                                                                 (normalize-fact-pattern form)
                                                         (if fact-err
                                                                         (format t "[add-fact] ~A~%" fact-err)
                                                                         (let* ((already (find-if (lambda (f)
                                                                                                                             (and (jarvis.knowledge:args-identical
                                                                                                                                   (jarvis.knowledge:fact-args f) args)
                                                                                                                                      (eq (jarvis.knowledge:fact-negative-p f) negative-p)))
                                                                                                                   (jarvis.knowledge:lookup-facts :predicate predicate :negative-p negative-p)))
                                                                                        (new-fact (apply #'jarvis.knowledge:make-fact predicate args))
                                                                                        (stored nil))
                                                                                 (setf (jarvis.knowledge:fact-negative-p new-fact) negative-p)
                                                                                 (setf stored (jarvis.knowledge:store-fact new-fact))
                                                                                 (if already
                                                                                                 (format t "[add-fact] Fact already exists as ~A: ~:[~;!~]~A(~{~A~^ ~})~%"
                                                                                                                 (jarvis.knowledge:fact-id stored)
                                                                                                                 (jarvis.knowledge:fact-negative-p stored)
                                                                                                                 (jarvis.knowledge:fact-predicate stored)
                                                                                                                 (jarvis.knowledge:fact-args stored))
                                                                                                 (format t "[add-fact] Added ~A: ~:[~;!~]~A(~{~A~^ ~})~%"
                                                                                                                 (jarvis.knowledge:fact-id stored)
                                                                                                                 (jarvis.knowledge:fact-negative-p stored)
                                                                                                                 (jarvis.knowledge:fact-predicate stored)
                                                                                                                 (jarvis.knowledge:fact-args stored)))
                                                                                 (save-persistent-state))))))))))

(defun handle-add-rule-command (line)
        "Handle: add-rule <name> <conditions> <conclusion>.
Example: add-rule human-implies-mortal ((human ?x)) (mortal ?x)"
        (let ((rest (command-rest line)))
                (if (string= rest "")
                                (format t "[add-rule] Usage: add-rule <name> ((cond1) ...) (conclusion)~%")
                                (multiple-value-bind (name-form pos1 err1)
                                                (parse-one-form rest)
                                        (cond
                                                (err1
                                                 (format t "[add-rule] Parse error (name): ~A~%" err1))
                                                ((or (eq name-form :eof) (not (symbolp name-form)))
                                                 (format t "[add-rule] Rule name must be a symbol. Example: human-implies-mortal~%"))
                                                (t
                                                 (multiple-value-bind (conditions pos2 err2)
                                                                 (parse-one-form rest pos1)
                                                         (cond
                                                                 (err2
                                                                  (format t "[add-rule] Parse error (conditions): ~A~%" err2))
                                                                 ((eq conditions :eof)
                                                                  (format t "[add-rule] Missing conditions. Example: ((human ?x))~%"))
                                                                 ((not (valid-conditions-p conditions))
                                                                  (format t "[add-rule] Conditions must be a list of patterns, e.g. ((human ?x) (mortal ?x)).~%"))
                                                                 (t
                                                                  (multiple-value-bind (conclusion pos3 err3)
                                                                                  (parse-one-form rest pos2)
                                                                          (cond
                                                                                  (err3
                                                                                   (format t "[add-rule] Parse error (conclusion): ~A~%" err3))
                                                                                  ((eq conclusion :eof)
                                                                                   (format t "[add-rule] Missing conclusion. Example: (mortal ?x)~%"))
                                                                                  ((not (valid-rule-conclusion-p conclusion))
                                                                                   (format t "[add-rule] Conclusion must be a pattern or negative form like (! dead ?x) or (!dead ?x).~%"))
                                                                                  ((not (string= (string-trim '(#\Space #\Tab) (subseq rest pos3)) ""))
                                                                                   (format t "[add-rule] Unexpected trailing input after conclusion.~%"))
                                                                                  (t
                                                                                   (handler-case
                                                                                       (let* ((rule (jarvis.knowledge:make-rule name-form conditions conclusion))
                                                                                              (stored (jarvis.knowledge:store-rule rule)))
                                                                                         (format t "[add-rule] Added ~A (~A): ~A => ~A~%"
                                                                                                 (jarvis.knowledge:rule-id stored)
                                                                                                 (jarvis.knowledge:rule-name stored)
                                                                                                 (jarvis.knowledge:rule-conditions stored)
                                                                                                 (rule-conclusion-expression-string stored))
                                                                                         (save-persistent-state))
                                                                                     (jarvis.knowledge:rule-error (err)
                                                                                       (format t "[add-rule] ~A~%"
                                                                                               (jarvis.knowledge:rule-error-message err))))))))))))))))

(defun legacy-jarvis-cli-handle-command (line)
        "Execute one CLI command line. Returns :QUIT to end the CLI loop." 
        (let* ((tokens (split-whitespace line))
                                 (cmd    (if tokens (string-downcase (first tokens)) "")))
                (cond
                        ((or (string= cmd "") (string= cmd ";"))
                         nil)
                        ((or (string= cmd "help") (string= cmd "commands"))
                         (print-cli-help))
                        ((string= cmd "demo")
                         (legacy-main)
                         (format t "[cli] Demo complete. You can now inspect with why/facts/rules.~%"))
                        ((string= cmd "status")
                         (format t "[status] facts=~A  rules=~A  traces=~A~%"
                                                         (length (jarvis.knowledge:all-facts))
                                                         (length (jarvis.knowledge:all-rules))
                                                         (length (jarvis.trace:all-traces))))
                        ((string= cmd "add-fact")
                         (handle-add-fact-command line))
                        ((string= cmd "add-rule")
                         (handle-add-rule-command line))
                        ((string= cmd "facts")
                         (list-facts-command))
                        ((string= cmd "rules")
                         (list-rules-command))
                        ((string= cmd "infer")
                         (let ((max-cycles (if (second tokens)
                                                                                                                 (parse-nonnegative-int (second tokens))
                                                                                                                 1000)))
                                 (if max-cycles
                                                 (run-inference-with-trace-and-tms :max-cycles max-cycles)
                                                 (format t "[infer] Usage: infer [non-negative-max-cycles]~%"))))
                        ((or (string= cmd "why") (string= cmd "wy"))
                         (handle-why-command tokens))
                           ((or (string= cmd "prove") (string= cmd "proof"))
                            (if (< (length tokens) 2)
                                              (format t "[prove] Usage: prove <fact-id>~%")
                                              (multiple-value-bind (fid fact)
                                                                 (parse-fact-token (second tokens))
                                                        (cond
                                                                 ((null fid)
                                                                         (format t "[prove] Could not parse fact id: ~A~%" (second tokens)))
                                                                 ((null fact)
                                                                         (format t "[prove] Fact ~A is not currently in the database.~%" fid))
                                                                 (t
                                                                         (explain-proof-forward fid))))))
                        ((string= cmd "retract")
                         (if (< (length tokens) 2)
                                         (format t "[retract] Usage: retract <fact-id>~%")
                                         (multiple-value-bind (fid fact)
                                                         (parse-fact-token (second tokens))
                                                 (cond
                                                         ((null fid)
                                                                (format t "[retract] Could not parse fact id: ~A~%" (second tokens)))
                                                         ((null fact)
                                                                (format t "[retract] Fact ~A is not currently in the database.~%" fid))
                                                         (t
                                                                (let ((removed (jarvis.truth-maintenance:retract-with-support fid)))
                                                                        (format t "[retract] Removed ~A fact(s): ~A~%"
                                                                                                                      (length removed) removed)
                                                                                  (save-persistent-state)))))))
                        ((string= cmd "reset")
                         (jarvis.knowledge:clear-databases)
                         (jarvis.truth-maintenance:clear-tms)
                         (jarvis.trace:clear-traces)
                            (save-persistent-state)
                         (format t "[reset] Cleared KB, TMS, and trace store.~%"))
                        ((or (string= cmd "quit") (string= cmd "exit"))
                         :quit)
                        (t
                         (format t "[cli] Unknown command: ~A. Type 'help' for commands.~%" cmd)))))

(defun legacy-jarvis-cli ()
        "Start an interactive command-line interface for inspecting and steering Jarvis."
        (load-persistent-state)
        (format t "~%Jarvis CLI ready. Type 'help' for commands. Type 'quit' to exit.~%")
        (loop
                (format t "jarvis> ")
                (finish-output)
                (let ((line (read-line *standard-input* nil :eof)))
                        (when (or (eq line :eof)
                                                                (eq (legacy-jarvis-cli-handle-command line) :quit))
                                (format t "[cli] Exiting Jarvis CLI.~%")
                                (return)))))

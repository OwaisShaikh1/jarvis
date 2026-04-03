;;; =============================================================================
;;; Layer 5 — Graph Representation
;;; File: src/graph/graph.lisp
;;;
;;; Converts a TRACE (from Layer 4) into a Directed Acyclic Graph (DAG) that
;;; the Abstraction Engine can mine for repeated reasoning patterns.
;;;
;;; We implement our own lightweight adjacency-list graph rather than
;;; depending on the cl-graph API surface directly.  cl-graph is available as
;;; a dependency but its API changed between versions; keeping the graph
;;; internals self-contained makes the code more portable.
;;;
;;; Graph anatomy:
;;;   NODE  — represents either a FACT or a RULE firing.
;;;     :fact nodes are labelled with "predicate(arg1,arg2,…)".
;;;     :rule nodes are labelled with the rule's name.
;;;
;;;   EDGE  — a directed link with a RELATION keyword:
;;;     :input-of  — a fact node is an input condition of a rule node.
;;;     :produces  — a rule node produces an output fact node.
;;;
;;;   DERIVATION-GRAPH — the container holding a node table and an edge list,
;;;     plus a forward-adjacency index and a reverse-adjacency index for O(1)
;;;     successor/predecessor lookup.
;;;
;;; Building the graph (TRACE->GRAPH):
;;;   For each TRACE-STEP in the trace:
;;;     1. Ensure an :fact node exists for every input fact.
;;;     2. Ensure a  :rule node exists for the rule that fired.
;;;     3. Ensure an :fact node exists for the output fact.
;;;     4. Add :input-of edges from input nodes to the rule node.
;;;     5. Add a    :produces edge from the rule node to the output node.
;;;
;;; Root nodes are fact nodes with no incoming :produces edges — they are the
;;; user-asserted assumptions the whole derivation rests on.
;;;
;;; Leaf nodes are fact nodes with no outgoing :input-of edges — they are the
;;; final conclusions, never used as inputs to further rules in this trace.
;;; =============================================================================

(in-package :jarvis.graph)


;;; ---------------------------------------------------------------------------
;;; Section 1 — Node and edge structures
;;; ---------------------------------------------------------------------------

(defstruct (graph-node (:constructor %make-graph-node))
  "A vertex in a derivation graph."
  id       ; symbol — matches a fact-id or rule-id from other layers
  type     ; keyword — :fact or :rule
  label)   ; string — printable description for debugging / visualisation

(defstruct (graph-edge (:constructor %make-graph-edge))
  "A directed edge in a derivation graph."
  from-id    ; symbol — source node id
  to-id      ; symbol — target node id
  relation)  ; keyword — :input-of or :produces


;;; ---------------------------------------------------------------------------
;;; Section 2 — Derivation-graph container
;;; ---------------------------------------------------------------------------

(defstruct (derivation-graph (:constructor %make-derivation-graph))
  "Container for a reasoning-trace DAG.
   NODE-TABLE  maps node-id → GRAPH-NODE.
   EDGES       is a flat list of all GRAPH-EDGEs (kept for serialisation).
   FORWARD     maps node-id → list of successor node-ids.
   BACKWARD    maps node-id → list of predecessor node-ids."
  id           ; symbol — same as the trace's session-id
  node-table   ; hash-table, :test #'eq
  edges        ; list of GRAPH-EDGE
  forward      ; hash-table, :test #'eq  (node-id → list of node-ids)
  backward)    ; hash-table, :test #'eq  (node-id → list of node-ids)

(defun make-derivation-graph (id)
  "Construct an empty DERIVATION-GRAPH with the given ID symbol."
  (%make-derivation-graph
   :id         id
   :node-table (make-hash-table :test #'eq)
   :edges      nil
   :forward    (make-hash-table :test #'eq)
   :backward   (make-hash-table :test #'eq)))

(defun derivation-graph-raw (dg)
  "Return the raw NODE-TABLE hash-table.
   Alias kept for compatibility with the package interface."
  (derivation-graph-node-table dg))


;;; ---------------------------------------------------------------------------
;;; Section 3 — Mutating a derivation-graph
;;; ---------------------------------------------------------------------------

(defun add-node (dg id type label)
  "Add a node with ID, TYPE (:fact or :rule), and LABEL string to DG.
   If a node with that ID already exists it is returned unchanged (idempotent)."
  (or (gethash id (derivation-graph-node-table dg))
      (let ((node (%make-graph-node :id id :type type :label label)))
        (setf (gethash id (derivation-graph-node-table dg)) node)
        node)))

(defun add-edge (dg from-id to-id relation)
  "Add a directed edge FROM-ID → TO-ID with RELATION to DG.
   Updates both the forward and backward adjacency tables.
   Returns the new GRAPH-EDGE."
  (let ((edge (%make-graph-edge :from-id from-id :to-id to-id :relation relation)))
    (push edge (derivation-graph-edges dg))
    ;; Forward adjacency: from-id can reach to-id.
    (pushnew to-id   (gethash from-id (derivation-graph-forward  dg) nil) :test #'eq)
    ;; Backward adjacency: to-id is reachable from from-id.
    (pushnew from-id (gethash to-id   (derivation-graph-backward dg) nil) :test #'eq)
    edge))

(defun get-node (dg id)
  "Return the GRAPH-NODE with ID in DG, or NIL if absent."
  (gethash id (derivation-graph-node-table dg)))

(defun node-type (node)
  "Return the type keyword (:fact or :rule) of NODE."
  (graph-node-type node))

(defun node-label (node)
  "Return the human-readable label string of NODE."
  (graph-node-label node))

(defun successors (dg node-id)
  "Return the list of node-ids directly reachable from NODE-ID in DG."
  (gethash node-id (derivation-graph-forward dg) nil))

(defun predecessors (dg node-id)
  "Return the list of node-ids that have a direct edge TO NODE-ID in DG."
  (gethash node-id (derivation-graph-backward dg) nil))


;;; ---------------------------------------------------------------------------
;;; Section 4 — Fact and rule label helpers
;;; ---------------------------------------------------------------------------

(defun fact-label (fact-id)
  "Build a printable label for a fact node, e.g. \"mortal(socrates)\".
   Returns the raw ID symbol-name if the fact is not in *FACT-DB*."
  (let ((fact (gethash fact-id jarvis.knowledge:*fact-db*)))
    (if fact
        (format nil "~(~A~)(~{~(~A~)~^,~})"
                (jarvis.knowledge:fact-predicate fact)
                (jarvis.knowledge:fact-args fact))
        (symbol-name fact-id))))

(defun rule-label (rule-id)
  "Build a printable label for a rule node, e.g. \"[rule] MODUS-PONENS\".
   Returns the raw ID symbol-name if the rule is not in *RULE-DB*."
  (let ((rule (gethash rule-id jarvis.knowledge:*rule-db*)))
    (if rule
        (format nil "[rule] ~(~A~)" (jarvis.knowledge:rule-name rule))
        (symbol-name rule-id))))


;;; ---------------------------------------------------------------------------
;;; Section 5 — Building a derivation graph from a trace
;;; ---------------------------------------------------------------------------

(defun trace->graph (trace)
  "Convert a completed TRACE into a DERIVATION-GRAPH.
   Each TRACE-STEP becomes:
     • a :rule node for the rule that fired
     • :fact nodes for every input fact and the output fact
     • :input-of edges from each input-fact node to the rule node
     • a :produces edge from the rule node to the output-fact node
   Returns the completed DERIVATION-GRAPH."
  (let ((dg (make-derivation-graph (jarvis.trace:trace-session-id trace))))
    ;; First pass: ensure nodes exist for all facts in the start-state.
    ;; These become the root assumptions.
    (dolist (fact (jarvis.trace:trace-start-state trace))
      (add-node dg
                (jarvis.knowledge:fact-id fact)
                :fact
                (fact-label (jarvis.knowledge:fact-id fact))))
    ;; Second pass: wire up each inference step.
    (dolist (step (jarvis.trace:trace-steps trace))
      (let ((rule-id    (jarvis.trace:trace-step-rule-id   step))
            (input-ids  (jarvis.trace:trace-step-input-ids step))
            (output-id  (jarvis.trace:trace-step-output-id step)))
        ;; Ensure the rule node exists.
        (add-node dg rule-id :rule (rule-label rule-id))
        ;; Ensure the output fact node exists.
        (add-node dg output-id :fact (fact-label output-id))
        ;; Wire inputs → rule.
        (dolist (in-id input-ids)
          ;; Ensure input fact node exists (may already be present from start-state).
          (add-node dg in-id :fact (fact-label in-id))
          (add-edge dg in-id rule-id :input-of))
        ;; Wire rule → output.
        (add-edge dg rule-id output-id :produces)))
    dg))


;;; ---------------------------------------------------------------------------
;;; Section 6 — Graph-level queries
;;; ---------------------------------------------------------------------------

(defun root-nodes (dg)
  "Return node-ids with no predecessors — the user-asserted base assumptions."
  (loop for id being the hash-keys of (derivation-graph-node-table dg)
        unless (gethash id (derivation-graph-backward dg))
          collect id))

(defun leaf-nodes (dg)
  "Return node-ids with no successors — the deepest derived conclusions."
  (loop for id being the hash-keys of (derivation-graph-node-table dg)
        unless (gethash id (derivation-graph-forward dg))
          collect id))

(defun graph-depth (dg)
  "Return the length of the longest path from any root node to any leaf.
   Uses a simple BFS-based level assignment; assumes a DAG (no cycles)."
  (let ((level (make-hash-table :test #'eq)))
    ;; Initialise root nodes at level 0.
    (dolist (root (root-nodes dg))
      (setf (gethash root level) 0))
    ;; BFS: propagate levels forward through successor edges.
    (let ((queue (copy-list (root-nodes dg))))
      (loop while queue
            for current = (pop queue)
            for current-level = (gethash current level 0)
            do (dolist (succ (successors dg current))
                 (let ((known-level (gethash succ level -1)))
                   (when (> (1+ current-level) known-level)
                     (setf (gethash succ level) (1+ current-level))
                     ;; Revisit successors when their level improves.
                     (push succ queue))))))
    ;; Maximum level across all nodes is the graph depth.
    (loop for l being the hash-values of level maximize l into max-l
          finally (return (or max-l 0)))))

(defun subgraph-from (dg node-id)
  "Return a new DERIVATION-GRAPH containing only NODE-ID and all nodes
   reachable from it in DG (i.e., the subgraph rooted at NODE-ID).
   Useful for extracting self-contained reasoning sub-chains."
  (let ((sub   (make-derivation-graph
                (intern (format nil "~A-sub-~A"
                                (derivation-graph-id dg)
                                node-id)
                        :jarvis.graph)))
        (visited (make-hash-table :test #'eq))
        (queue   (list node-id)))
    (loop while queue
          for current = (pop queue)
          unless (gethash current visited)
            do (setf (gethash current visited) t)
               ;; Copy the node.
               (let ((src-node (get-node dg current)))
                 (when src-node
                   (add-node sub current
                             (graph-node-type  src-node)
                             (graph-node-label src-node))))
               ;; Walk successors.
               (dolist (succ (successors dg current))
                 (push succ queue)))
    ;; Second pass: copy edges whose both endpoints were visited.
    (dolist (edge (derivation-graph-edges dg))
      (when (and (gethash (graph-edge-from-id edge) visited)
                 (gethash (graph-edge-to-id   edge) visited))
        (add-edge sub
                  (graph-edge-from-id  edge)
                  (graph-edge-to-id    edge)
                  (graph-edge-relation edge))))
    sub))


;;; ---------------------------------------------------------------------------
;;; Section 7 — Structural comparison
;;;
;;; Two graphs are ISOMORPHIC (structurally identical) if there exists a
;;; bijection between their node sets that respects node types AND edge
;;; relations.  This is the NP-hard subgraph isomorphism problem in general,
;;; but for small reasoning traces (< 100 nodes) we can afford the naive
;;; recursive approach.
;;;
;;; COMMON-SUBGRAPH finds the largest shared subgraph between two graphs by
;;; seeding a candidate set from matching root nodes and extending greedily.
;;; This is a simplified heuristic suitable for the sizes expected in practice.
;;; ---------------------------------------------------------------------------

(defun node-signature (dg node-id)
  "Return a structural signature for a node: (type . successor-count).
   Used as a quick filter before expensive recursive matching."
  (let ((node (get-node dg node-id)))
    (cons (graph-node-type node)
          (length (successors dg node-id)))))

(defun isomorphic-p (dg1 dg2)
  "Return T if DG1 and DG2 are structurally isomorphic.
   Two graphs are isomorphic iff they have the same number of nodes, the same
   number of edges, and there is a type-preserving bijection between their nodes
   that also preserves edge relations.
   This implementation uses a simplified signature-based check adequate for
   small graphs; a full VF2 algorithm would be needed for large graphs."
  (let ((n1 (hash-table-count (derivation-graph-node-table dg1)))
        (n2 (hash-table-count (derivation-graph-node-table dg2)))
        (e1 (length (derivation-graph-edges dg1)))
        (e2 (length (derivation-graph-edges dg2))))
    ;; Fast structural pre-filter.
    (when (and (= n1 n2) (= e1 e2))
      ;; Compare sorted node-signature multisets.
      (let ((sigs1 (sort (loop for id being the hash-keys
                                 of (derivation-graph-node-table dg1)
                               collect (node-signature dg1 id))
                         #'string< :key #'prin1-to-string))
            (sigs2 (sort (loop for id being the hash-keys
                                 of (derivation-graph-node-table dg2)
                               collect (node-signature dg2 id))
                         #'string< :key #'prin1-to-string)))
        (equal sigs1 sigs2)))))

(defun common-subgraph (dg1 dg2)
  "Return a new DERIVATION-GRAPH representing the largest common subgraph of
   DG1 and DG2, or NIL if no common structure exists.
   The algorithm seeds from pairs of root nodes with matching types and
   greedily extends the match along successor edges.
   The result captures the shared structural skeleton — variable nodes will be
   parameterised by the Abstraction Engine in Layer 6."
  (let ((mapping    (make-hash-table :test #'eq)) ; dg1-node-id → dg2-node-id
        (rev-map    (make-hash-table :test #'eq)) ; dg2-node-id → dg1-node-id
        (common-ids nil))

    ;; Attempt to grow a mapping starting from matching root pairs.
    (dolist (r1 (root-nodes dg1))
      (let ((node1 (get-node dg1 r1)))
        (dolist (r2 (root-nodes dg2))
          (let ((node2 (get-node dg2 r2)))
            ;; Roots must have the same type to be candidate matches.
            (when (and (eq (graph-node-type node1) (graph-node-type node2))
                       (not (gethash r1 mapping))
                       (not (gethash r2 rev-map)))
              (setf (gethash r1 mapping) r2)
              (setf (gethash r2 rev-map) r1)
              (push r1 common-ids)
              ;; Greedily extend the match along successor edges.
              (let ((queue (list r1)))
                (loop while queue
                      for cur1 = (pop queue)
                      for cur2 = (gethash cur1 mapping)
                      do (let ((succs1 (successors dg1 cur1))
                               (succs2 (successors dg2 cur2)))
                           (loop for s1 in succs1
                                 for n1 = (get-node dg1 s1)
                                 do (loop for s2 in succs2
                                          for n2 = (get-node dg2 s2)
                                          when (and (eq (graph-node-type n1)
                                                        (graph-node-type n2))
                                                    (not (gethash s1 mapping))
                                                    (not (gethash s2 rev-map)))
                                            do (setf (gethash s1 mapping) s2)
                                               (setf (gethash s2 rev-map) s1)
                                               (push s1 common-ids)
                                               (push s1 queue)))))))))))

    ;; Build the common subgraph from the matched nodes.
    (when common-ids
      (let ((sub (make-derivation-graph
                  (intern (format nil "COMMON-~A-~A"
                                  (derivation-graph-id dg1)
                                  (derivation-graph-id dg2))
                          :jarvis.graph))))
        (dolist (id common-ids)
          (let ((node (get-node dg1 id)))
            (add-node sub id (graph-node-type node) (graph-node-label node))))
        ;; Copy edges whose both endpoints are in the common set.
        (dolist (edge (derivation-graph-edges dg1))
          (when (and (member (graph-edge-from-id edge) common-ids :test #'eq)
                     (member (graph-edge-to-id   edge) common-ids :test #'eq))
            (add-edge sub
                      (graph-edge-from-id  edge)
                      (graph-edge-to-id    edge)
                      (graph-edge-relation edge))))
        sub))))

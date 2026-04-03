(asdf:defsystem "jarvis"
  :description "Symbolic AI reasoning system with knowledge representation, inference, and abstraction."
  :version "0.1.0"
  :depends-on ("cl-graph" "alexandria" "cl-ppcre")
  :serial t   ; each component is compiled/loaded in the order listed below
  :components
  (;; Layer 1 — Knowledge Representation
   ;; package.lisp declares the defpackage; knowledge.lisp implements it.
   (:module "src/knowledge"
    :serial t
    :components ((:file "package")
                 (:file "knowledge")))

   ;; Layer 2 — Inference Engine
   (:module "src/inference"
    :serial t
    :components ((:file "package")
                 (:file "inference")))

   ;; Layer 3 — Truth Maintenance System (JTMS)
   (:module "src/truth-maintenance"
    :serial t
    :components ((:file "package")
                 (:file "tms")))

   ;; Layer 4 — Trace Recorder
   (:module "src/trace"
    :serial t
    :components ((:file "package")
                 (:file "trace")))

   ;; Layer 5 — Graph Representation (builds on trace)
   (:module "src/graph"
    :serial t
    :components ((:file "package")
                 (:file "graph")))

   ;; Layers 6–10 — stubs, ready for implementation
   (:module "src/abstraction"
    :components ((:file "package")))
   (:module "src/macro-formation"
    :components ((:file "package")))
   (:module "src/principle-optimizer"
    :components ((:file "package")))
   (:module "src/memory-pruning"
    :components ((:file "package")))
   (:module "src/meta-controller"
    :components ((:file "package")))))

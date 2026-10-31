(asdf:defsystem "jarvis-plane"
  :description "2D geometry and physics plane for Jarvis."
  :depends-on ("jarvis")
  :serial t
  :pathname "src/"
  :components ((:file "package")
               (:file "numeric")
               (:file "units")
               (:file "expr")
               (:file "model")
               (:file "algebra-protocol")
               (:file "algebra-native")
               (:file "algebra-maxima")
               (:file "algebra-crosscheck")
               (:file "numerics")
               (:file "sim")
               (:file "laws")
               (:file "infer")
               (:file "explain")
               (:file "svg")
               (:file "export")
               (:file "cli")))

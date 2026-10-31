(asdf:defsystem "jarvis-tests"
  :depends-on ("jarvis" "fiveam")
  :serial t
  :pathname ""
  :components ((:file "package")
               (:file "core-tests")))

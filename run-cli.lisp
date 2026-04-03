;;; run-cli.lisp — interactive terminal shell for Jarvis
;;;
;;; Usage from the project root:
;;;   sbcl --load "run-cli.lisp"
;;;
;;; This script loads the system, runs the demo once to populate facts/traces,
;;; then opens the interactive CLI.

(pushnew #P"c:/Users/OWAIS/MyStuff/Projects/AAAA My projects/AI/jarvis/"
         asdf:*central-registry* :test #'equal)

(asdf:load-system "jarvis")
(load "main.lisp")

(main)
(format t "~%[run-cli] Demo state prepared. Entering CLI...~%")
(jarvis-cli)

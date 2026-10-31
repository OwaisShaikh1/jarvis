;;; run-cli.lisp — interactive terminal shell for Jarvis
;;;
;;; Usage from the project root:
;;;   sbcl --load "run-cli.lisp"
;;;
;;; This script loads the system, runs the demo once to populate facts/traces,
;;; then opens the interactive CLI.

(require :asdf)
(defparameter cl-user::*jarvis-root*
  (make-pathname :name nil :type nil :version nil :defaults *load-truename*))
(pushnew cl-user::*jarvis-root* asdf:*central-registry* :test #'equal)

(asdf:load-system "jarvis")
(load (merge-pathnames "main.lisp" cl-user::*jarvis-root*))

(main)
(format t "~%[run-cli] Demo state prepared. Entering CLI...~%")
(jarvis-cli)

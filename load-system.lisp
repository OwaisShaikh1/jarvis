;;; Load the jarvis system for development
;;;
;;; Usage from a shell:
;;;   sbcl --load "load-system.lisp"  (drops you into an interactive REPL)
;;;
;;; From an already-running SBCL REPL:
;;;   (load "load-system.lisp")
;;;
;;; To also run the demo immediately, see run.lisp instead.

;;; Register the project root with ASDF so it can find jarvis.asd.
(require :asdf)
(defparameter cl-user::*jarvis-root*
  (make-pathname :name nil :type nil :version nil :defaults *load-truename*))
(pushnew cl-user::*jarvis-root* asdf:*central-registry* :test #'equal)

;;; Compile and load all layers in the order declared in jarvis.asd.
(asdf:load-system "jarvis")

(format t "~%Jarvis system loaded. Call (load (merge-pathnames \"main.lisp\" cl-user::*jarvis-root*)) then (main) to run the demo.~%")

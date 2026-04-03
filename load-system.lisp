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
(pushnew #P"c:/Users/OWAIS/MyStuff/Projects/AAAA My projects/AI/jarvis/"
         asdf:*central-registry* :test #'equal)

;;; Compile and load all layers in the order declared in jarvis.asd.
(asdf:load-system "jarvis")

(format t "~%Jarvis system loaded. Call (load \"main.lisp\") then (main) to run the demo.~%")

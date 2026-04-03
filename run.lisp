;;; run.lisp — one-shot demo runner
;;;
;;; Loads the jarvis system, runs the five-layer demonstration, then exits.
;;;
;;; Usage from the project root:
;;;   sbcl --non-interactive --load "run.lisp"
;;;
;;; Everything printed to stdout comes from the layer implementations and
;;; the MAIN function in main.lisp.  No interactive input is required.

;;; Step 1 — Register the project so ASDF can find jarvis.asd.
(pushnew #P"c:/Users/OWAIS/MyStuff/Projects/AAAA My projects/AI/jarvis/"
         asdf:*central-registry* :test #'equal)

;;; Step 2 — Compile and load all five layers.
(asdf:load-system "jarvis")

;;; Step 3 — Load the demo entry point.
(load "main.lisp")

;;; Step 4 — Run the demo.
(main)

;;; Step 5 — Exit cleanly.
(quit)

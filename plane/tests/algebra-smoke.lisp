(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(let ((backend (make-instance 'jarvis.plane.algebra:native-backend)))
  (format t "simplify: ~S~%"
          (jarvis.plane.algebra:alg-simplify backend '(+ 2 (* 3 x) 1)))
  (format t "diff: ~S~%"
          (jarvis.plane.algebra:alg-diff backend '(* x x) 'x))
  (format t "solve: ~S~%"
          (jarvis.plane.algebra:alg-solve
           backend '(= (+ (expt x 2) (* -5 x) 6) 0) 'x)))
(format t "jarvis-plane algebra smoke test completed.~%")
(quit)

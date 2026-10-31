(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(let ((native (make-instance 'jarvis.plane.algebra:native-backend)))
  (assert (equal (jarvis.plane.algebra:alg-simplify native '(+ 1 2))
                 3)))
(let ((maxima (jarvis.plane.algebra:make-maxima-backend
               :executable "definitely-not-installed-maxima")))
  (handler-case
      (jarvis.plane.algebra:alg-simplify maxima '(+ 1 2))
    (jarvis.plane.algebra:backend-unavailable ()
      (format t "Maxima unavailable is reported explicitly.~%"))))
(assert (null (jarvis.cli:jarvis-cli-handle-command
               "algebra-backend native")))
(format t "jarvis-plane algebra backend smoke tests passed.~%")
(quit)

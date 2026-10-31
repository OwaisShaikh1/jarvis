(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(jarvis.plane.model:clear-plane)
(jarvis.plane.model:add-entity 'ball 'particle
                               :params '((mass 1d0) (v0 10d0)
                                         (angle 0.7853981633974483d0)))
(multiple-value-bind (id trajectory)
    (jarvis.plane.sim:simulate 'ball :ballistic 1d0 0.05d0)
  (declare (ignore trajectory))
  (let ((first (merge-pathnames "plane-test-1.svg"
                                (truename ".")))
        (second (merge-pathnames "plane-test-2.svg"
                                 (truename "."))))
    (jarvis.plane.svg:write-svg id first)
    (jarvis.plane.svg:write-svg id second)
    (with-open-file (a first) (with-open-file (b second)
      (assert (equal (read-line a nil) (read-line b nil)))
      (assert (search "<polyline" (format nil "~{~A~%~}"
                                           (loop for line = (read-line a nil)
                                                 while line collect line))))))
    (delete-file first)
    (delete-file second)))
(format t "jarvis-plane SVG smoke tests passed.~%")
(quit)

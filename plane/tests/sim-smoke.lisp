(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(jarvis.plane.model:clear-plane)
(jarvis.plane.model:def-entity-type 'particle
  :params '(mass drag x0 y0 v0 angle))
(jarvis.plane.model:add-entity
 'ball 'particle
 :params '((mass 1d0) (drag 0d0) (x0 0d0) (y0 0d0)
           (v0 10d0) (angle 0.7853981633974483d0)))
(jarvis.plane.model:set-param 'world 'g 9.81d0)

(multiple-value-bind (id trajectory)
    (jarvis.plane.sim:simulate 'ball :ballistic 2d0 0.01d0)
  (assert (jarvis.plane.sim:trajectory-p trajectory))
  (assert (gethash id jarvis.plane.sim:*trajectories*))
  (assert (find-if
           (lambda (fact)
             (equal (third (jarvis.knowledge:fact-args fact)) :range))
           (jarvis.plane.sim:trajectory-summaries trajectory))))

(assert (= (length (jarvis.plane.laws:laws)) 18))
(jarvis.plane.laws:enable-law 'spring-period)
(assert (jarvis.plane.laws:law-enabled-p
         (jarvis.plane.laws:law 'spring-period)))
(jarvis.plane.laws:disable-law 'spring-period)
(format t "jarvis-plane simulation smoke tests passed.~%")
(quit)

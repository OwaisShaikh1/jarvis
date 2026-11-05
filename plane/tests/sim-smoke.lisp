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

(defun simulation-summary-value (trajectory key)
  "Return one numeric summary value from TRAJECTORY."
  (let ((fact (find key (jarvis.plane.sim:trajectory-summaries trajectory)
                     :key (lambda (item)
                            (third (jarvis.knowledge:fact-args item)))
                     :test #'eq)))
    (when fact (fourth (jarvis.knowledge:fact-args fact)))))

(jarvis.plane.model:add-entity
 'ballistic-test 'particle
 :params '((mass 1d0) (drag 0d0) (x0 0d0) (y0 0d0)
           (v0 20d0) (angle 0.7853981633974483d0)))
(multiple-value-bind (id trajectory)
    (jarvis.plane.sim:simulate 'ballistic-test :ballistic 5d0 0.05d0)
  (assert (jarvis.plane.sim:trajectory-p trajectory))
  (assert (gethash id jarvis.plane.sim:*trajectories*))
  (assert (eq (jarvis.plane.sim:trajectory-status trajectory) :event))
  (assert (< (abs (- (simulation-summary-value trajectory :range)
                     40.77472d0)) 1d-4))
  (assert (< (abs (- (simulation-summary-value trajectory :apex-height)
                     10.19368d0)) 1d-4))
  (assert (< (abs (- (simulation-summary-value trajectory :apex-time)
                     1.4416d0)) 1d-4))
  (assert (< (abs (- (simulation-summary-value trajectory :flight-time)
                     2.88321d0)) 1d-4)))

(jarvis.plane.model:add-entity
 'incline-test 'incline
 :params '((angle 0.5235987755982988d0) (mu 0.2d0) (distance 5d0)))
(multiple-value-bind (id trajectory)
    (jarvis.plane.sim:simulate 'incline-test :incline-slide 3d0 0.05d0)
  (declare (ignore id))
  (assert (eq (jarvis.plane.sim:trajectory-status trajectory) :event))
  (assert (< (abs (- (simulation-summary-value trajectory :final-s)
                     5d0)) 1d-8))
  (assert (< (abs (- (simulation-summary-value trajectory :final-t)
                     1.76614d0)) 1d-4)))

(assert (= (length (jarvis.plane.laws:laws)) 18))
(assert (< (abs (- (jarvis.plane.laws:evaluate-law
                    'spring-period '(:mass 2d0 :k 50d0))
                   1.2566370614359172d0))
           1d-12))
(assert (< (abs (- (jarvis.plane.laws:evaluate-law
                    'projectile-range
                    '(:v0 10d0 :angle 0.7853981633974483d0 :g 9.81d0))
                   10.19367991845056d0))
           1d-10))
(jarvis.plane.laws:enable-law 'spring-period)
(assert (jarvis.plane.laws:law-enabled-p
         (jarvis.plane.laws:law 'spring-period)))
(jarvis.plane.laws:disable-law 'spring-period)
(format t "jarvis-plane simulation smoke tests passed.~%")
(quit)

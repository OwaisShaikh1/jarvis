(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(jarvis.plane.model:clear-plane)
(jarvis.plane.model:add-entity 'spring 'spring
                               :params '((mass 2d0) (k 40d0)))
(jarvis.plane.infer:observe 'spring 'spring-period 1.4049629462081452d0
                             :sigma 1d-8)
(let ((report (jarvis.plane.infer:infer-params 'spring '(k))))
  (assert (eq (getf report :status) :converged))
  (assert (< (abs (- (aref (getf report :estimates) 0) 40d0)) 1d-5)))
(format t "jarvis-plane inference smoke tests passed.~%")
(quit)

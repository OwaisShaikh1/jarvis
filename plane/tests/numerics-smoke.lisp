(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(multiple-value-bind (state steps)
    (jarvis.plane.numerics:rk4
     (lambda (time y) (declare (ignore time)) (vector (- (aref y 0))))
     0d0 #(1d0) 1d0 0.01d0)
  (declare (ignore steps))
  (assert (< (abs (- (aref state 0) (exp -1d0))) 1d-6)))

(multiple-value-bind (times states status stats)
    (jarvis.plane.numerics:rk45
     (lambda (time y) (declare (ignore time)) (vector (- (aref y 0))))
     0d0 #(1d0) 1d0 :rtol 1d-9 :atol 1d-12)
  (declare (ignore times stats))
  (assert (eq status :converged))
  (assert (< (abs (- (aref (car (last states)) 0) (exp -1d0))) 1d-7)))

(multiple-value-bind (solution status iterations residual)
    (jarvis.plane.numerics:newton-solve
     (lambda (x) (vector (- (* (aref x 0) (aref x 0)) 2d0)))
     #(1d0))
  (declare (ignore iterations))
  (assert (eq status :converged))
  (assert (< (abs (- (aref solution 0) (sqrt 2d0))) 1d-10))
  (assert (< residual 1d-10)))

(let ((fit (jarvis.plane.numerics:levenberg-marquardt
            (lambda (p)
              (vector (- (aref p 1) 3d0)
                      (- (+ (aref p 0) (aref p 1)) 5d0)
                      (- (+ (* 2d0 (aref p 0)) (aref p 1)) 7d0)))
            #(0d0 0d0))))
  (assert (eq (getf fit :status) :converged))
  (assert (< (abs (- (aref (getf fit :p) 0) 2d0)) 1d-8))
  (assert (< (abs (- (aref (getf fit :p) 1) 3d0)) 1d-8)))

(format t "jarvis-plane numerical smoke tests passed.~%")
(quit)

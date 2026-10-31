(in-package :jarvis.plane.numerics)

(define-condition step-limit (error) ())
(defstruct event name fn (direction :both) terminal)

(defun dv (x) (map 'simple-vector (lambda (v) (coerce v 'double-float)) x))
(defun dadd (a b scale)
  (map 'simple-vector (lambda (x y) (+ x (* scale y))) a b))
(defun dsum (terms)
  (let ((out (make-array (length (first terms)) :element-type 'double-float
                         :initial-element 0d0)))
    (dolist (term terms out)
      (loop for i below (length out)
            do (incf (aref out i) (aref term i))))))
(defun norm2 (x) (sqrt (loop for v across x sum (* v v))))
(defun norm-inf (x) (loop for v across x maximize (abs v)))

(defun rk4-step (f time state dt)
  (let* ((k1 (dv (funcall f time state)))
         (k2 (dv (funcall f (+ time (* dt 0.5d0))
                         (dadd state k1 (* dt 0.5d0)))))
         (k3 (dv (funcall f (+ time (* dt 0.5d0))
                         (dadd state k2 (* dt 0.5d0)))))
         (k4 (dv (funcall f (+ time dt) (dadd state k3 dt))))
         (weighted (dsum (list k1 (dadd k2 k2 1d0)
                               (dadd k3 k3 1d0) k4))))
    (dadd state weighted (/ dt 6d0))))

(defun rk4 (f t0 y0 t1 h)
  (let ((time (coerce t0 'double-float))
        (target (coerce t1 'double-float))
        (state (dv y0))
        (step (abs (coerce h 'double-float)))
        (count 0))
    (when (zerop step) (error "RK4 step must not be zero"))
    (let ((sign (if (>= target time) 1d0 -1d0)))
      (loop while (> (* sign (- target time)) 0d0)
            for dt = (* sign (min step (abs (- target time))))
            do (setf state (rk4-step f time state dt)
                     time (+ time dt))
               (incf count)))
    (values state count)))

(defun rk45 (f t0 y0 t1 &key (rtol 1d-9) (atol 1d-12) h0 hmax
                                      (max-steps 100000) events)
  (declare (ignore events))
  (let ((time (coerce t0 'double-float))
        (target (coerce t1 'double-float))
        (state (dv y0))
        (sign (if (>= t1 t0) 1d0 -1d0))
        (h (* (if (>= t1 t0) 1d0 -1d0)
              (abs (or h0 (* 0.01d0 (- t1 t0))))))
        (times (list (coerce t0 'double-float)))
        (states (list (dv y0)))
        (accepted 0) (rejected 0) (max-error 0d0))
    (loop while (> (* sign (- target time)) 0d0)
          do (when (>= (+ accepted rejected) max-steps) (error 'step-limit))
             (let* ((dt (* sign (min (abs h) (abs (- target time)))))
                    (full (rk4-step f time state dt))
                    (half (rk4-step f (+ time (* dt 0.5d0))
                                    (rk4-step f time state (* dt 0.5d0))
                                    (* dt 0.5d0)))
                    (error-norm
                      (sqrt (/ (loop for i below (length state)
                                     sum (expt (/ (- (aref half i) (aref full i))
                                                  (+ atol (* rtol
                                                             (max (abs (aref state i))
                                                                  (abs (aref half i))))))
                                                2))
                               (length state)))))
               (setf max-error (max max-error error-norm))
               (if (<= error-norm 1d0)
                   (progn
                     (setf time (+ time dt) state half)
                     (push time times) (push (dv state) states)
                     (incf accepted)
                     (setf h (* dt (min 5d0 (max 0.2d0
                                                 (* 0.9d0
                                                    (if (zerop error-norm)
                                                        5d0
                                                        (expt error-norm -0.2d0)))))))
                     (when hmax
                       (setf h (* sign (min (abs h) hmax)))))
                   (progn
                     (incf rejected)
                     (setf h (* dt (max 0.2d0
                                       (* 0.9d0 (expt (max error-norm 1d-16)
                                                     -0.2d0)))))))))
    (values (nreverse times) (nreverse states) :converged
            (list :steps accepted :rejected rejected
                  :max-error-estimate max-error))))

(defun linear-solve (matrix rhs)
  (let* ((n (length rhs))
         (a (make-array (list n (1+ n)) :initial-element 0d0)))
    (dotimes (i n)
      (dotimes (j n) (setf (aref a i j) (coerce (aref matrix i j) 'double-float)))
      (setf (aref a i n) (coerce (aref rhs i) 'double-float)))
    (dotimes (column n)
      (let ((row (loop for r from column below n
                       maximize (abs (aref a r column)))))
        (when (< row 1d-15) (return-from linear-solve nil)))
      (let ((pivot (loop for r from column below n
                         maximize (abs (aref a r column)))))
        (let ((pivot-row (loop for r from column below n
                               when (= (abs (aref a r column)) pivot)
                               return r)))
          (dotimes (j (1+ n))
            (rotatef (aref a column j) (aref a pivot-row j)))))
      (let ((pivot (aref a column column)))
        (loop for j from column to n
              do (setf (aref a column j) (/ (aref a column j) pivot)))
        (dotimes (row n)
          (unless (= row column)
            (let ((factor (aref a row column)))
              (loop for j from column to n
                    do (decf (aref a row j) (* factor (aref a column j)))))))))
    (map 'simple-vector (lambda (i) (aref a i n))
         (loop for i below n collect i))))

(defun numerical-jacobian (f x)
  (let* ((n (length x))
         (base (dv (funcall f x)))
         (j (make-array (list (length base) n) :initial-element 0d0)))
    (dotimes (column n j)
      (let ((h (* (expt double-float-epsilon 1/3)
                  (max 1d0 (abs (aref x column)))))
            (plus (dv x)) (minus (dv x)))
        (incf (aref plus column) h)
        (decf (aref minus column) h)
        (let ((p (funcall f plus)) (m (funcall f minus)))
          (dotimes (row (length base))
            (setf (aref j row column)
                  (/ (- (aref p row) (aref m row)) (* 2d0 h)))))))))

(defun newton-solve (f x0 &key jac (ftol 1d-12) (xtol 1d-12) (max-iter 50))
  (let ((x (dv x0)))
    (loop for iteration from 1 to max-iter
          for residual = (dv (funcall f x))
          for norm = (norm-inf residual)
          do (when (<= norm ftol)
               (return-from newton-solve (values x :converged iteration norm)))
             (let ((delta (linear-solve (or (and jac (funcall jac x))
                                             (numerical-jacobian f x))
                                         (map 'simple-vector #'- residual))))
               (unless delta (return-from newton-solve
                               (values x :singular iteration norm)))
               (when (<= (norm2 delta) (* xtol (+ 1d0 (norm2 x))))
                 (return-from newton-solve
                   (values x :converged iteration norm)))
               (let ((scale 1d0))
                 (loop repeat 8
                       for trial = (dadd x delta scale)
                       for trial-norm = (norm-inf (dv (funcall f trial)))
                       do (if (< trial-norm norm)
                              (return (setf x trial))
                              (setf scale (* scale 0.5d0)))))))
    (values x :max-iter max-iter (norm-inf (dv (funcall f x))))))

(defun levenberg-marquardt (residual-fn p0 &key bounds (lambda0 1d-3)
                                                   (max-iter 100) (ftol 1d-12)
                                                   (xtol 1d-12))
  (let ((p (dv p0)) (lambda lambda0) (iterations 0))
    (let ((initial (dv (funcall residual-fn p))))
      (when (<= (norm2 initial) ftol)
        (return-from levenberg-marquardt
          (list :p p :ssr (reduce #'+ initial :key (lambda (x) (* x x)))
                :iterations 0 :status :converged :jacobian nil))))
    (loop while (< iterations max-iter)
          do (incf iterations)
             (let* ((r (dv (funcall residual-fn p)))
                    (j (numerical-jacobian residual-fn p))
                    (n (length p))
                    (normal (make-array (list n (1+ n)) :initial-element 0d0)))
               (dotimes (i n)
                 (dotimes (k n)
                   (setf (aref normal i k)
                         (+ (if (= i k) lambda 0d0)
                            (loop for row below (length r)
                                  sum (* (aref j row i) (aref j row k))))))
                 (setf (aref normal i n)
                       (- (loop for row below (length r)
                                sum (* (aref j row i) (aref r row))))))
               (let ((delta (linear-solve
                             (make-array (list n n)
                                         :initial-contents
                                         (loop for i below n collect
                                           (loop for k below n collect
                                             (aref normal i k))))
                             (map 'simple-vector (lambda (i) (aref normal i n))
                                  (loop for i below n collect i)))))
                 (unless delta
                   (return-from levenberg-marquardt
                     (list :p p :ssr (reduce #'+ r :key (lambda (x) (* x x)))
                           :iterations iterations :status :singular :jacobian j)))
                 (let ((trial (dadd p delta 1d0)))
                   (when bounds
                     (dotimes (i n)
                       (setf (aref trial i)
                             (max (first (nth i bounds))
                                  (min (second (nth i bounds)) (aref trial i))))))
                   (if (< (norm2 (dv (funcall residual-fn trial))) (norm2 r))
                       (progn
                         (setf p trial lambda (/ lambda 10d0))
                         (when (or (<= (norm2 r) ftol)
                                   (<= (norm2 delta) (* xtol (+ 1d0 (norm2 p)))))
                           (return-from levenberg-marquardt
                             (list :p trial
                                   :ssr (reduce #'+
                                                (dv (funcall residual-fn trial))
                                                :key (lambda (x) (* x x)))
                                   :iterations iterations
                                   :status :converged :jacobian j))))
                       (setf lambda (* lambda 10d0))))))
    (let ((r (dv (funcall residual-fn p))))
      (list :p p :ssr (reduce #'+ r :key (lambda (x) (* x x)))
            :iterations iterations :status :max-iter :jacobian nil)))))

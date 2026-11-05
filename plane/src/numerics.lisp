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

(defun %combine-state (state step weighted-derivatives)
  "Return a weighted Runge-Kutta stage from STATE and derivatives."
  (let ((result (dv state)))
    (dolist (term weighted-derivatives result)
      (let ((weight (first term))
            (derivative (second term)))
        (loop for index below (length result)
              do (incf (aref result index)
                       (* step weight (aref derivative index))))))))

(defun %dormand-prince-step (f time state step first-derivative)
  "Compute one Dormand-Prince 5(4) step and its FSAL derivatives."
  (let* ((k1 (or first-derivative (dv (funcall f time state))))
         (k2 (dv (funcall f (+ time (* step 1/5))
                         (%combine-state state step
                                         (list (list 1/5 k1))))))
         (k3 (dv (funcall f (+ time (* step 3/10))
                         (%combine-state state step
                                         (list (list 3/40 k1)
                                               (list 9/40 k2))))))
         (k4 (dv (funcall f (+ time (* step 4/5))
                         (%combine-state state step
                                         (list (list 44/45 k1)
                                               (list -56/15 k2)
                                               (list 32/9 k3))))))
         (k5 (dv (funcall f (+ time (* step 8/9))
                         (%combine-state state step
                                         (list (list 19372/6561 k1)
                                               (list -25360/2187 k2)
                                               (list 64448/6561 k3)
                                               (list -212/729 k4))))))
         (k6 (dv (funcall f (+ time step)
                         (%combine-state state step
                                         (list (list 9017/3168 k1)
                                               (list -355/33 k2)
                                               (list 46732/5247 k3)
                                               (list 49/176 k4)
                                               (list -5103/18656 k5))))))
         (fifth-order
           (%combine-state state step
                           (list (list 35/384 k1)
                                 (list 500/1113 k3)
                                 (list 125/192 k4)
                                 (list -2187/6784 k5)
                                 (list 11/84 k6))))
         (k7 (dv (funcall f (+ time step) fifth-order)))
         (fourth-order
           (%combine-state state step
                           (list (list 5179/57600 k1)
                                 (list 7571/16695 k3)
                                 (list 393/640 k4)
                                 (list -92097/339200 k5)
                                 (list 187/2100 k6)
                                 (list 1/40 k7))))
         (error-estimate (map 'simple-vector #'- fifth-order fourth-order)))
    (values fifth-order error-estimate k1 k7)))

(defun %error-norm (error-estimate old-state new-state rtol atol)
  "Return the RMS scaled error estimate for one candidate step."
  (sqrt (/ (loop for index below (length old-state)
                 for scale = (+ atol (* rtol
                                        (max (abs (aref old-state index))
                                             (abs (aref new-state index)))))
                 sum (expt (/ (aref error-estimate index) scale) 2))
           (length old-state))))

(defun %event-value (event time state)
  "Evaluate EVENT at TIME and STATE as a double-float."
  (let ((value (funcall (event-fn event) time state)))
    (unless (realp value)
      (error "Event ~A returned a non-real value" (event-name event)))
    (coerce value 'double-float)))

(defun %event-crossing-p (event old-value new-value)
  "Report whether EVENT crosses zero in its configured direction."
  (case (event-direction event)
    (:rising (or (and (< old-value 0d0) (>= new-value 0d0))
                 (and (= old-value 0d0) (> new-value 0d0))))
    (:falling (or (and (> old-value 0d0) (<= new-value 0d0))
                  (and (= old-value 0d0) (< new-value 0d0))))
    (:both (or (and (< old-value 0d0) (>= new-value 0d0))
               (and (> old-value 0d0) (<= new-value 0d0))
               (and (= old-value 0d0) (/= new-value 0d0))))
    (otherwise (error "Unknown event direction ~A" (event-direction event)))))

(defun %hermite-state (theta old-state new-state old-derivative new-derivative step)
  "Interpolate a step state at THETA with cubic Hermite interpolation."
  (let* ((theta2 (* theta theta))
         (theta3 (* theta2 theta))
         (h00 (+ (* 2d0 theta3) (* -3d0 theta2) 1d0))
         (h10 (+ theta3 (* -2d0 theta2) theta))
         (h01 (+ (* -2d0 theta3) (* 3d0 theta2)))
         (h11 (- theta3 theta2)))
    (map 'simple-vector
         (lambda (y0 y1 f0 f1)
           (+ (* h00 y0) (* h10 step f0)
              (* h01 y1) (* h11 step f1)))
         old-state new-state old-derivative new-derivative)))

(defun %locate-event (event old-time old-state old-derivative
                      new-time new-state new-derivative event-tol)
  "Locate EVENT within an accepted step; return its time and state."
  (let* ((old-value (%event-value event old-time old-state))
         (new-value (%event-value event new-time new-state)))
    (when (%event-crossing-p event old-value new-value)
      (let* ((step (- new-time old-time))
             (low 0d0)
             (high 1d0)
             (low-value old-value))
        (unless (zerop old-value)
          (loop repeat 100
                for middle = (/ (+ low high) 2d0)
                for middle-time = (+ old-time (* middle step))
                while (> (abs (* (- high low) step)) event-tol)
                do (let* ((middle-state
                            (%hermite-state middle old-state new-state
                                            old-derivative new-derivative step))
                          (middle-value
                            (%event-value event middle-time middle-state)))
                     (if (or (zerop middle-value)
                             (minusp (* low-value middle-value)))
                         (setf high middle)
                         (setf low middle
                               low-value middle-value))))
        (let* ((theta (if (zerop old-value) 0d0 (/ (+ low high) 2d0)))
               (event-time (+ old-time (* theta step)))
               (event-state (%hermite-state theta old-state new-state
                                            old-derivative new-derivative step)))
          (list event theta event-time event-state)))))))

(defun rk45 (f t0 y0 t1 &key (rtol 1d-9) (atol 1d-12) h0 hmax
                                      (max-steps 100000) events
                                      (event-tol 1d-12))
  "Integrate F with Dormand-Prince 5(4), returning samples and event data."
  (let* ((start (coerce t0 'double-float))
         (target (coerce t1 'double-float))
         (span (- target start))
         (direction (if (minusp span) -1d0 1d0))
         (time start)
         (state (dv y0))
         (initial-step (or h0 (* 0.01d0 span)))
         (step (* direction (abs (coerce initial-step 'double-float))))
         (times (list start))
         (states (list (dv y0)))
         (accepted 0)
         (rejected 0)
         (max-error 0d0)
         (first-derivative nil)
         (event-records nil)
         (terminated nil))
    (unless (and (plusp rtol) (plusp atol) (plusp event-tol))
      (error "RK45 tolerances must be positive"))
    (unless (and (integerp max-steps) (plusp max-steps))
      (error "RK45 max-steps must be a positive integer"))
    (when (and hmax (not (plusp hmax)))
      (error "RK45 hmax must be positive"))
    (when (and (not (zerop span)) (zerop step))
      (error "RK45 initial step must not be zero"))
    (dolist (event events) (check-type event event))
    (when hmax (setf step (* direction (min (abs step) hmax))))
    (loop while (and (not terminated)
                     (> (* direction (- target time)) 0d0))
          do (when (>= (+ accepted rejected) max-steps)
               (error 'step-limit))
             (let* ((remaining (- target time))
                    (dt (* direction (min (abs step) (abs remaining)))))
               (when (= (+ time dt) time)
                 (error "RK45 step size underflow at t=~A" time))
               (multiple-value-bind (candidate error-estimate k1 k7)
                   (%dormand-prince-step f time state dt first-derivative)
                 (let ((error-norm (%error-norm error-estimate state candidate
                                                rtol atol)))
                   (setf max-error (max max-error error-norm))
                   (if (<= error-norm 1d0)
                       (let* ((next-time (+ time dt))
                              (crossings
                                (stable-sort
                                 (loop for event in events
                                       for crossing =
                                         (%locate-event event time state k1
                                                        next-time candidate k7
                                                        event-tol)
                                       when crossing collect crossing)
                                 #'< :key #'second))
                              (terminal (find-if
                                         (lambda (crossing)
                                           (event-terminal (first crossing)))
                                         crossings))
                              (kept-crossings
                                (if terminal
                                    (loop for crossing in crossings
                                          while (<= (second crossing)
                                                    (second terminal))
                                          collect crossing)
                                    crossings)))
                         (dolist (crossing kept-crossings)
                           (push (list (event-name (first crossing))
                                       (third crossing) (fourth crossing))
                                 event-records))
                         (incf accepted)
                         (if terminal
                             (setf time (third terminal)
                                   state (fourth terminal)
                                   terminated t)
                             (setf time next-time
                                   state candidate
                                   first-derivative k7))
                         (unless (= time (first times))
                           (push time times)
                           (push (dv state) states))
                         (let ((factor
                                 (if (zerop error-norm)
                                     5d0
                                     (min 5d0
                                          (max 0.2d0
                                               (* 0.9d0
                                                  (expt error-norm -0.2d0)))))))
                           (setf step (* dt factor))
                           (when hmax
                             (setf step (* direction
                                           (min (abs step) hmax))))))
                       (progn
                         (incf rejected)
                         (setf first-derivative k1
                               step (* dt
                                       (max 0.2d0
                                            (* 0.9d0
                                               (expt (max error-norm 1d-16)
                                                     -0.2d0))))))))))
    )
    (values (nreverse times) (nreverse states)
            (if terminated :event :converged)
            (list :steps accepted :rejected rejected
                  :max-error-estimate max-error
                  :method :dormand-prince-5-4
                  :events (nreverse event-records)))))
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

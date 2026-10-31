(in-package :jarvis.plane.laws)

(defstruct law name doc assumes formula enabled-p)
(defparameter *law-registry* (make-hash-table :test #'eq))

(defun %lookup (name)
  (or (gethash name *law-registry*)
      (loop for entry being the hash-values of *law-registry*
            when (string-equal (symbol-name name)
                               (symbol-name (law-name entry)))
              return entry)))

(defun %register (name doc formula &optional assumes)
  (setf (gethash name *law-registry*)
        (make-law :name name :doc doc :assumes assumes :formula formula))
  name)

(defun law (name)
  (%lookup name))

(defun laws ()
  (loop for entry being the hash-values of *law-registry*
        collect entry))

(defun enable-law (name)
  (let ((entry (%lookup name)))
    (unless entry (error "Unknown law ~A" name))
    (setf (law-enabled-p entry) t)
    entry))

(defun disable-law (name)
  (let ((entry (%lookup name)))
    (unless entry (error "Unknown law ~A" name))
    (setf (law-enabled-p entry) nil)
    entry))

(defun %value (bindings key)
  (or (getf bindings key)
      (error "Missing value ~A for law evaluation" key)))

(defun evaluate-law (name bindings)
  (let ((entry (%lookup name)))
    (unless entry (error "Unknown law ~A" name))
    (funcall (law-formula entry) bindings)))

(defun apply-enabled-laws (&optional bindings)
  (loop for entry being the hash-values of *law-registry*
        when (law-enabled-p entry)
          collect (list (law-name entry)
                        (funcall (law-formula entry) bindings))))

(%register 'distance "Euclidean distance between two points."
           (lambda (b)
             (sqrt (+ (expt (- (%value b :x2) (%value b :x1)) 2)
                      (expt (- (%value b :y2) (%value b :y1)) 2)))))
(%register 'slope "Slope of a line through two points."
           (lambda (b)
             (/ (- (%value b :y2) (%value b :y1))
                (- (%value b :x2) (%value b :x1)))))
(%register 'polygon-area "Polygon area by the shoelace formula."
           (lambda (b)
             (let ((points (%value b :points)))
               (/ (abs (loop for (x1 y1) in points
                             for (x2 y2) in (append (rest points)
                                                    (list (first points)))
                             sum (- (* x1 y2) (* y1 x2))))
                  2d0))))
(%register 'circle-tangent-line "Tangent line to a circle."
           (lambda (b)
             (let* ((a (- (%value b :px) (%value b :cx)))
                    (c (- (* a (%value b :px))
                          (* (- (%value b :py) (%value b :cy))
                             (%value b :py)))))
               (list a (- (%value b :py) (%value b :cy)) c))))
(%register 'line-circle-intersects "Line/circle intersection test."
           (lambda (b)
             (<= (/ (abs (+ (* (%value b :a) (%value b :cx))
                            (* (%value b :b) (%value b :cy))
                            (%value b :c)))
                    (sqrt (+ (expt (%value b :a) 2)
                             (expt (%value b :b) 2))))
                 (%value b :r))))
(%register 'v-final "Constant-acceleration final velocity."
           (lambda (b) (+ (%value b :u) (* (%value b :a) (%value b :t)))))
(%register 'displacement "Constant-acceleration displacement."
           (lambda (b) (+ (* (%value b :u) (%value b :t))
                          (* 0.5d0 (%value b :a) (expt (%value b :t) 2)))))
(%register 'v2 "Velocity squared relation."
           (lambda (b) (+ (expt (%value b :u) 2)
                          (* 2d0 (%value b :a) (%value b :s)))))
(%register 'projectile-range "Drag-free projectile range."
           (lambda (b) (/ (* (expt (%value b :v0) 2)
                             (sin (* 2d0 (%value b :angle))))
                          (%value b :g))))
(%register 'projectile-apex "Drag-free projectile apex."
           (lambda (b) (/ (* (expt (%value b :v0) 2)
                             (expt (sin (%value b :angle)) 2))
                          (* 2d0 (%value b :g)))))
(%register 'projectile-time "Drag-free projectile flight time."
           (lambda (b) (/ (* 2d0 (%value b :v0) (sin (%value b :angle)))
                          (%value b :g))))
(%register 'circular-period "Uniform circular-motion period."
           (lambda (b) (/ (* 2d0 pi (%value b :r)) (%value b :v))))
(%register 'newton-2 "Newton's second law."
           (lambda (b) (/ (%value b :force) (%value b :mass))))
(%register 'incline-acceleration "Incline acceleration."
           (lambda (b) (* (%value b :g)
                         (- (sin (%value b :angle))
                            (* (%value b :mu) (cos (%value b :angle)))))))
(%register 'hooke-force "Hooke's law."
           (lambda (b) (- (* (%value b :k) (%value b :x)))))
(%register 'spring-period "Simple harmonic oscillator period."
           (lambda (b) (* 2d0 pi (sqrt (/ (%value b :mass)
                                         (%value b :k))))))
(%register 'kinetic-energy "Kinetic energy."
           (lambda (b) (* 0.5d0 (%value b :mass)
                          (expt (%value b :v) 2))))
(%register 'torque-alpha "Angular acceleration from torque."
           (lambda (b) (/ (%value b :tau) (%value b :inertia))))

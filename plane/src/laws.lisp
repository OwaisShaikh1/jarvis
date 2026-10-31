(in-package :jarvis.plane.laws)

(defstruct law name doc assumes formula enabled-p)
(defparameter *law-registry* (make-hash-table :test #'eq))

(defun %lookup (name)
  (or (gethash name *law-registry*)
      (loop for entry being the hash-values of *law-registry*
            when (string-equal (symbol-name name)
                               (symbol-name (law-name entry)))
              return entry)))

(defun %register (name doc assumes formula)
  (setf (gethash name *law-registry*)
        (make-law :name name :doc doc :assumes assumes :formula formula))
  name)

(defun law (name)
  (%lookup name))

(defun laws ()
  (loop for law being the hash-values of *law-registry*
        collect law))

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

(defun apply-enabled-laws ()
  (loop for entry being the hash-values of *law-registry*
        when (law-enabled-p entry)
          append (funcall (law-formula entry))))

(%register 'distance "Euclidean distance between two points." nil
           (lambda () nil))
(%register 'slope "Slope of a line through two points." nil
           (lambda () nil))
(%register 'polygon-area "Polygon area by the shoelace formula." nil
           (lambda () nil))
(%register 'circle-tangent-line "Tangent line to a circle." nil
           (lambda () nil))
(%register 'line-circle-intersects "Line/circle intersection test." nil
           (lambda () nil))
(%register 'v-final "Constant-acceleration final velocity." nil (lambda () nil))
(%register 'displacement "Constant-acceleration displacement." nil (lambda () nil))
(%register 'v2 "Velocity squared relation." nil (lambda () nil))
(%register 'projectile-range "Drag-free projectile range." nil (lambda () nil))
(%register 'projectile-apex "Drag-free projectile apex." nil (lambda () nil))
(%register 'projectile-time "Drag-free projectile flight time." nil (lambda () nil))
(%register 'circular-period "Uniform circular-motion period." nil (lambda () nil))
(%register 'newton-2 "Newton's second law." nil (lambda () nil))
(%register 'incline-acceleration "Incline acceleration." nil (lambda () nil))
(%register 'hooke-force "Hooke's law." nil (lambda () nil))
(%register 'spring-period "Simple harmonic oscillator period." nil (lambda () nil))
(%register 'kinetic-energy "Kinetic energy." nil (lambda () nil))
(%register 'torque-alpha "Angular acceleration from torque." nil (lambda () nil))

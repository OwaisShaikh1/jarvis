(in-package :jarvis.plane.algebra)

(defclass crosscheck-backend ()
  ((primary :initarg :primary :initform (make-instance 'native-backend)
            :reader crosscheck-primary)
   (secondary :initarg :secondary :initform (make-maxima-backend)
              :reader crosscheck-secondary)))

(defun make-crosscheck-backend (&key primary secondary)
  (make-instance 'crosscheck-backend
                 :primary (or primary (make-instance 'native-backend))
                 :secondary (or secondary (make-maxima-backend))))

(defun %crosscheck (backend operation &rest args)
  (let ((primary (apply operation (crosscheck-primary backend) args))
        (secondary (apply operation (crosscheck-secondary backend) args)))
    (unless (equal primary secondary)
      (error "Algebra cross-check mismatch: ~S vs ~S" primary secondary))
    primary))

(defmethod alg-simplify ((backend crosscheck-backend) expression)
  (%crosscheck backend #'alg-simplify expression))

(defmethod alg-substitute ((backend crosscheck-backend) expression bindings)
  (%crosscheck backend #'alg-substitute expression bindings))

(defmethod alg-diff ((backend crosscheck-backend) expression variable)
  (%crosscheck backend #'alg-diff expression variable))

(defmethod alg-solve ((backend crosscheck-backend) equation variable)
  (%crosscheck backend #'alg-solve equation variable))

(defmethod alg-evaluate ((backend crosscheck-backend) expression bindings policy)
  (%crosscheck backend #'alg-evaluate expression bindings policy))

(defmethod alg-capabilities ((backend crosscheck-backend))
  (list :cross-check t
        :primary (alg-capabilities (crosscheck-primary backend))
        :secondary (alg-capabilities (crosscheck-secondary backend))))

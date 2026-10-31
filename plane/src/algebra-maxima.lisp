(in-package :jarvis.plane.algebra)

(defclass maxima-backend ()
  ((executable :initarg :executable :initform "maxima"
               :reader maxima-executable)))

(defun make-maxima-backend (&key (executable "maxima"))
  (make-instance 'maxima-backend :executable executable))

(defun maxima-available-p (&optional (backend (make-maxima-backend)))
  (handler-case
      (progn
        (uiop:run-program (list "where" (maxima-executable backend))
                          :output 'string :error-output nil
                          :ignore-error-status nil)
        t)
    (error () nil)))

(defun %maxima-unavailable (backend)
  (error 'backend-unavailable :backend backend))

(defmethod alg-simplify ((backend maxima-backend) expression)
  (declare (ignore expression))
  (%maxima-unavailable backend))

(defmethod alg-substitute ((backend maxima-backend) expression bindings)
  (declare (ignore expression bindings))
  (%maxima-unavailable backend))

(defmethod alg-diff ((backend maxima-backend) expression variable)
  (declare (ignore expression variable))
  (%maxima-unavailable backend))

(defmethod alg-solve ((backend maxima-backend) equation variable)
  (declare (ignore equation variable))
  (%maxima-unavailable backend))

(defmethod alg-evaluate ((backend maxima-backend) expression bindings policy)
  (declare (ignore expression bindings policy))
  (%maxima-unavailable backend))

(defmethod alg-capabilities ((backend maxima-backend))
  (declare (ignore backend))
  '(:available :external-maxima :diff t :solve :external :simplify :external))

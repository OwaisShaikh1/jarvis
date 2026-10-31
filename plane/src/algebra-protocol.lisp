(in-package :jarvis.plane.algebra)

(define-condition cannot-solve (error)
  ((expression :initarg :expression :reader cannot-solve-expression)))

(define-condition backend-unavailable (error)
  ((backend :initarg :backend :reader unavailable-backend)))

(defclass native-backend () ())

(defparameter *algebra-backend* (make-instance 'native-backend))

(defgeneric alg-simplify (backend expression))
(defgeneric alg-substitute (backend expression bindings))
(defgeneric alg-diff (backend expression variable))
(defgeneric alg-solve (backend equation variable))
(defgeneric alg-evaluate (backend expression bindings policy))
(defgeneric alg-capabilities (backend))

(defmacro with-backend ((backend) &body body)
  `(let ((*algebra-backend* ,backend))
     ,@body))

(defun to-canonical (expression)
  (cond
    ((atom expression) expression)
    ((eq (first expression) '-)
     (if (rest (rest expression))
         `(+ ,(to-canonical (second expression))
             (* -1 ,(to-canonical (third expression))))
         `(* -1 ,(to-canonical (second expression)))))
    ((eq (first expression) '/)
     `(* ,(to-canonical (second expression))
         (expt ,(to-canonical (third expression)) -1)))
    (t (cons (first expression) (mapcar #'to-canonical (rest expression))))))

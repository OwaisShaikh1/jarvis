(in-package :jarvis.plane.algebra)

(defun operator (expression)
  (and (consp expression) (first expression)))

(defun numeric-zero-p (x) (and (numberp x) (zerop x)))
(defun numeric-one-p (x) (and (numberp x) (= x 1)))

(defun expression< (a b)
  (cond
    ((and (numberp a) (numberp b)) (< a b))
    ((numberp a) t)
    ((numberp b) nil)
    ((and (symbolp a) (symbolp b))
     (string< (symbol-name a) (symbol-name b)))
    ((symbolp a) t)
    ((symbolp b) nil)
    (t (string< (prin1-to-string (operator a))
                (prin1-to-string (operator b))))))

(defun simplify-add (terms)
  (let* ((flat (mapcan (lambda (x)
                         (if (and (consp x) (eq (operator x) '+))
                             (copy-list (rest x))
                             (list x)))
                       terms))
         (constant (reduce #'+ (remove-if-not #'numberp flat) :initial-value 0))
         (others (remove-if #'numberp flat))
         (groups (make-hash-table :test #'equal)))
    (dolist (term others)
      (let ((coefficient 1)
            (base term))
        (when (and (consp term) (eq (operator term) '*)
                   (numberp (second term)))
          (setf coefficient (second term)
                base (if (cddr (cddr term)) (cons '* (cddr term))
                         (third term))))
        (incf (gethash base groups 0) coefficient)))
    (setf others
          (loop for base being the hash-keys of groups
                for coefficient = (gethash base groups)
                unless (zerop coefficient)
                  collect (cond ((= coefficient 1) base)
                                ((and (numberp base) nil) (* coefficient base))
                                (t `(* ,coefficient ,base)))))
    (let ((result (if (zerop constant) others (cons constant others))))
    (setf result (remove-if #'numeric-zero-p result))
    (cond ((null result) 0)
          ((null (rest result)) (first result))
          (t (cons '+ (sort result #'expression<)))))))

(defun simplify-mul (terms)
  (let* ((flat (mapcan (lambda (x)
                         (if (and (consp x) (eq (operator x) '*))
                             (copy-list (rest x))
                             (list x)))
                       terms)))
    (when (some #'numeric-zero-p flat)
      (return-from simplify-mul 0))
    (let ((constant (reduce #'* (remove-if-not #'numberp flat) :initial-value 1))
          (others (remove-if #'numberp flat)))
      (when (zerop constant) (return-from simplify-mul 0))
      (let ((result (if (= constant 1) others (cons constant others))))
        (cond ((null result) 1)
              ((null (rest result)) (first result))
              (t (cons '* (sort result #'expression<))))))))

(defmethod alg-simplify ((backend native-backend) expression)
  (declare (ignore backend))
  (cond
    ((atom expression) expression)
    (t
     (let* ((op (operator expression))
            (args (mapcar (lambda (x)
                            (alg-simplify *algebra-backend* x))
                          (rest expression))))
       (case op
         (+ (simplify-add args))
         (* (simplify-mul args))
         (- (alg-simplify *algebra-backend* (to-canonical expression)))
         (/ (alg-simplify *algebra-backend* (to-canonical expression)))
         (expt (cond ((and (numeric-one-p (second args))) (first args))
                     ((and (numberp (first args)) (numberp (second args)))
                      (expt (first args) (second args)))
                     ((numeric-zero-p (second args)) 1)
                     (t (cons 'expt args))))
         (sqrt (if (numberp (first args))
                   (let ((value (sqrt (first args))))
                     (if (= value (round value)) (round value)
                         (cons 'sqrt args)))
                   (cons 'sqrt args)))
         (otherwise (cons op args)))))))

(defmethod alg-substitute ((backend native-backend) expression bindings)
  (declare (ignore backend))
  (if (atom expression)
      (let ((cell (assoc expression bindings :test #'eq)))
        (if cell (cdr cell) expression))
      (alg-simplify *algebra-backend*
                    (cons (first expression)
                          (mapcar (lambda (x)
                                    (alg-substitute *algebra-backend* x bindings))
                                  (rest expression))))))

(defmethod alg-diff ((backend native-backend) expression variable)
  (declare (ignore backend))
  (cond
    ((numberp expression) 0)
    ((symbolp expression) (if (eq expression variable) 1 0))
    (t
     (let ((op (operator expression))
           (args (rest expression)))
       (case op
         (+ (alg-simplify *algebra-backend*
                         (cons '+ (mapcar (lambda (x)
                                            (alg-diff *algebra-backend* x variable))
                                          args))))
         (* (alg-simplify
             *algebra-backend*
             (cons '+ (loop for i from 0 below (length args)
                            collect
                            (cons '*
                                  (loop for x in args
                                        for j from 0
                                        collect (if (= i j)
                                                    (alg-diff *algebra-backend*
                                                              x variable)
                                                    x)))))))
         (expt (let ((base (first args))
                     (power (second args)))
                 (if (numberp power)
                     (alg-simplify *algebra-backend*
                                   `(* ,power (expt ,base ,(1- power))
                                       ,(alg-diff *algebra-backend*
                                                  base variable)))
                     (alg-simplify *algebra-backend*
                                   `(* (expt ,base ,power)
                                       (log ,base)
                                       ,(alg-diff *algebra-backend*
                                                  power variable))))))
         (sin `(* (cos ,(first args))
                  ,(alg-diff *algebra-backend* (first args) variable)))
         (cos `(* -1 (sin ,(first args))
                  ,(alg-diff *algebra-backend* (first args) variable)))
         (exp `(* (exp ,(first args))
                  ,(alg-diff *algebra-backend* (first args) variable)))
         (log `(* (expt ,(first args) -1)
                  ,(alg-diff *algebra-backend* (first args) variable)))
         (sqrt `(* 1/2 (expt ,(first args) -1/2)
                   ,(alg-diff *algebra-backend* (first args) variable)))
         (otherwise
          (error 'cannot-solve :expression expression)))))))

(defun polynomial-coefficients (expression variable)
  (let ((e (alg-simplify *algebra-backend* expression))
        (coefficients (make-hash-table)))
    (labels ((add (degree coefficient)
               (incf (gethash degree coefficients 0) coefficient))
             (walk (term multiplier)
               (cond
                 ((numberp term) (add 0 (* multiplier term)))
                 ((eq term variable) (add 1 multiplier))
                 ((and (consp term) (eq (operator term) 'expt)
                       (eq (first (rest term)) variable)
                       (integerp (second (rest term))))
                  (add (second (rest term)) multiplier))
                 ((and (consp term) (eq (operator term) '+))
                  (dolist (x (rest term)) (walk x multiplier)))
                 ((and (consp term) (eq (operator term) '*))
                  (let ((degree 0) (constant multiplier))
                    (dolist (x (rest term))
                      (cond ((numberp x) (setf constant (* constant x)))
                            ((eq x variable) (incf degree))
                            ((and (consp x) (eq (operator x) 'expt)
                                  (eq (first (rest x)) variable))
                             (incf degree (second (rest x))))
                            (t (return-from walk nil))))
                    (add degree constant)))))
             (result ()
               (loop for degree from 0 to 2
                     collect (gethash degree coefficients 0))))
      (walk e 1)
      (result))))

(defmethod alg-solve ((backend native-backend) equation variable)
  (declare (ignore backend))
  (unless (and (consp equation) (eq (operator equation) '=))
    (error 'cannot-solve :expression equation))
  (let* ((difference (alg-simplify
                     *algebra-backend*
                     `(- ,(second equation) ,(third equation))))
         (coefficients (polynomial-coefficients difference variable))
         (a (third coefficients))
         (b (second coefficients))
         (c (first coefficients)))
    (cond
      ((and (zerop a) (zerop b))
       (if (zerop c) (list '(:exact t))
           (error 'cannot-solve :expression equation)))
      ((zerop a)
       (list (list :exact (alg-simplify *algebra-backend* `(- (/ ,c ,b))))))
      (t
       (let ((discriminant (- (* b b) (* 4 a c))))
         (list (list :exact
                     (alg-simplify *algebra-backend*
                                   `(/ (+ (- ,b) (sqrt ,discriminant))
                                       ,(* 2 a))))
               (list :exact
                     (alg-simplify *algebra-backend*
                                   `(/ (- (- ,b) (sqrt ,discriminant))
                                       ,(* 2 a))))))))))

(defmethod alg-evaluate ((backend native-backend) expression bindings policy)
  (declare (ignore backend))
  (jarvis.plane.expr:evaluate expression bindings :policy policy))

(defmethod alg-capabilities ((backend native-backend))
  (declare (ignore backend))
  '(:diff t :solve (:linear :quadratic) :simplify t :substitute t))

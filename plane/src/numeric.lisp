(in-package :jarvis.plane.numeric)

(defstruct (numeric-policy (:constructor %make-numeric-policy))
  (domain :double)
  (match :exact)
  (abs-eps 1d-12)
  (rel-eps 1d-9)
  (ulps 4)
  (dedup :exact)
  (traps '(:invalid :overflow :divide-by-zero))
  display-digits
  (seed 12345))

(defparameter *policies* (make-hash-table :test #'equal))

(defun make-numeric-policy (&key (domain :double) (match :exact)
                              (abs-eps 1d-12) (rel-eps 1d-9) (ulps 4)
                              (dedup :exact) (traps '(:invalid :overflow :divide-by-zero))
                              display-digits (seed 12345))
  (%make-numeric-policy :domain domain :match match :abs-eps abs-eps
                        :rel-eps rel-eps :ulps ulps :dedup dedup
                        :traps traps :display-digits display-digits :seed seed))

(defparameter *default-policy* (make-numeric-policy))

(defun set-policy (scope policy)
  (setf (gethash scope *policies*) policy))

(defun effective-policy (predicate position pattern-args)
  (or (gethash (list :pred predicate position) *policies*)
      (when (and (eq predicate 'param) (= position 2)
                 (first pattern-args))
        (gethash (list :param-kind (first pattern-args)) *policies*))
      (gethash (list :pred predicate) *policies*)
      (gethash :global *policies*)
      *default-policy*))

(defun numbers-match-p (a b policy)
  (unless (and (realp a) (realp b))
    (return-from numbers-match-p nil))
  (case (numeric-policy-match policy)
    (:exact (= a b))
    (:absolute (<= (abs (- a b)) (numeric-policy-abs-eps policy)))
    (:relative (or (= a b)
                   (<= (abs (- a b))
                       (* (numeric-policy-rel-eps policy)
                          (max (abs a) (abs b))))))
    (:combined (<= (abs (- a b))
                   (max (numeric-policy-abs-eps policy)
                        (* (numeric-policy-rel-eps policy)
                           (max (abs a) (abs b))))))
    (:ulps (and (= (coerce a 'double-float) (coerce b 'double-float))
                (<= (abs (- (round (* (coerce a 'double-float) 4503599627370496d0))
                            (round (* (coerce b 'double-float) 4503599627370496d0))))
                    (numeric-policy-ulps policy))))
    (otherwise (error "Unknown numeric matching mode ~S"
                      (numeric-policy-match policy)))))

(defun install-term-equality-hook ()
  (setf jarvis.knowledge:*term-equal-hook*
        (lambda (a b)
          (when (and (realp a) (realp b))
            (let* ((context jarvis.knowledge:*match-context*)
                   (predicate (first context))
                   (position (second context))
                   (pattern (third context)))
              (if (numbers-match-p a b
                                   (effective-policy predicate position pattern))
                  :equal
                  :unequal))))))

(install-term-equality-hook)

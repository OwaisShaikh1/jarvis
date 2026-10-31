(in-package :jarvis.tests)

(defparameter *test-data-dir*
  (merge-pathnames "jarvis-tests/" (uiop:temporary-directory)))

(defmacro with-clean-kb (&body body)
  `(progn
     (ensure-directories-exist *test-data-dir*)
     (let ((cl-user::*data-dir* *test-data-dir*))
       (declare (ignore cl-user::*data-dir*))
       (jarvis.knowledge:clear-databases)
       (jarvis.truth-maintenance:clear-tms)
       (jarvis.trace:clear-traces)
       ,@body)))

(defun find-fact (predicate &rest args)
  (find-if (lambda (fact)
             (and (eq (jarvis.knowledge:fact-predicate fact) predicate)
                  (equal (jarvis.knowledge:fact-args fact) args)))
           (jarvis.knowledge:all-facts)))

(test negative
  (with-clean-kb
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'alive 'plato))
    (jarvis.knowledge:store-rule
     (jarvis.knowledge:make-rule
      'alive-implies-!dead
      '((alive ?x))
      '(!dead ?x)))
    (jarvis.inference:run-inference)
    (let ((fact (find-fact 'dead 'plato)))
      (is fact)
      (is (jarvis.knowledge:fact-negative-p fact))
      (is (jarvis.knowledge:fact-derived-p fact)))))

(test negative-contradiction
  (with-clean-kb
    (let ((alive (jarvis.knowledge:store-fact
                  (jarvis.knowledge:make-fact 'alive 'plato)))
          (dead (jarvis.knowledge:store-fact
                 (jarvis.knowledge:make-fact 'dead 'plato))))
      (jarvis.knowledge:store-rule
       (jarvis.knowledge:make-rule
        'alive-implies-!dead
        '((alive ?x))
        '(!dead ?x)))
      (jarvis.inference:run-inference)
      (jarvis.truth-maintenance:register-contradiction
       (jarvis.knowledge:fact-id alive)
       (jarvis.knowledge:fact-id dead))
      (is-true (jarvis.truth-maintenance:check-contradictions)))))

(test root-cause
  (with-clean-kb
    (let ((human (jarvis.knowledge:store-fact
                  (jarvis.knowledge:make-fact 'human 'harsh)))
          (not-mortal (jarvis.knowledge:store-fact
                       (jarvis.knowledge:make-fact '!mortal 'harsh))))
      (jarvis.knowledge:store-rule
       (jarvis.knowledge:make-rule
        'human-implies-mortal
        '((human ?x))
        '(mortal ?x)))
      (jarvis.truth-maintenance:register-contradiction
       (jarvis.knowledge:fact-id human)
       (jarvis.knowledge:fact-id not-mortal))
      (jarvis.inference:run-inference)
      (let ((output (with-output-to-string (*standard-output*)
                      (jarvis.truth-maintenance:check-contradictions))))
        (is-true (search "Option 1" output))
        (is-true (search "Option 2" output))))))

(test p1-numeric-equality (:expected-failure "P1: numbers use EQUAL")
  (with-clean-kb
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'mass 'b1 2))
    (jarvis.knowledge:store-rule
     (jarvis.knowledge:make-rule 'mass-match '((mass ?b 2.0)) '(matched ?b)))
    (jarvis.inference:run-inference)
    (is (find-fact 'matched 'b1))))

(test p2-recursive-expression
  (with-clean-kb
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'distance 'b1 10))
    (jarvis.knowledge:store-rule
     (jarvis.knowledge:make-rule
      'nested
      '((distance ?b ?d))
      '(speed ?b (/ ?d 2))))
    (jarvis.inference:run-inference)
    (is (find-fact 'speed 'b1 '(/ 10 2)))))

(test p3-nil-binding
  (with-clean-kb
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'p 'a nil))
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'q 'a 'z))
    (jarvis.knowledge:store-rule
     (jarvis.knowledge:make-rule 'join '((p ?x ?y) (q ?x ?y)) '(joined ?x)))
    (jarvis.inference:run-inference)
    (is (null (find-fact 'joined 'a)))))

(test p4-multiple-justifications (:expected-failure "P4: one justification per fact")
  (with-clean-kb
    (let ((human (jarvis.knowledge:store-fact
                  (jarvis.knowledge:make-fact 'human 'a)))
          (mortal-rule (jarvis.knowledge:make-rule
                        'human-mortal '((human ?x)) '(mortal ?x))))
      (jarvis.knowledge:store-rule mortal-rule)
      (jarvis.knowledge:store-fact
       (jarvis.knowledge:make-fact 'immortal 'a))
      (jarvis.knowledge:store-rule
       (jarvis.knowledge:make-rule
        'immortal-mortal '((immortal ?x)) '(mortal ?x)))
      (jarvis.inference:run-inference)
      (jarvis.truth-maintenance:retract-with-support
       (jarvis.knowledge:fact-id human))
      (is (find-fact 'mortal 'a)))))

(test p5-inference-records-justifications (:expected-failure "P5: inference bypasses TMS")
  (with-clean-kb
    (let ((root (jarvis.knowledge:store-fact
                 (jarvis.knowledge:make-fact 'human 'a))))
      (jarvis.knowledge:store-rule
       (jarvis.knowledge:make-rule 'mortal '((human ?x)) '(mortal ?x)))
      (jarvis.engine:infer :quiet t)
      (let ((derived (find-fact 'mortal 'a)))
        (is derived)
        (is (jarvis.truth-maintenance:justification-for
             (jarvis.knowledge:fact-id derived)))
        (is root)))))

(test p6-no-rereporting
  (with-clean-kb
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'human 'a))
    (jarvis.knowledge:store-rule
     (jarvis.knowledge:make-rule 'mortal '((human ?x)) '(mortal ?x)))
    (jarvis.inference:run-inference)
    (is (null (jarvis.inference:run-inference)))))

(test p7-ground-condition
  (with-clean-kb
    (jarvis.knowledge:store-fact
     (jarvis.knowledge:make-fact 'alive 'plato))
    (jarvis.knowledge:store-rule
     (jarvis.knowledge:make-rule 'ground '((alive plato)) '(ok plato)))
    (jarvis.inference:run-inference)
    (is (find-fact 'ok 'plato))))

(test p8-range-restriction
  (with-clean-kb
    (signals jarvis.knowledge:rule-error
      (jarvis.knowledge:make-rule
       'unbound '((human ?x)) '(likes ?x ?y)))))

(test p9-empty-variable-name
  (is-false (jarvis.inference::variable-p (make-symbol ""))))

(test reader-safety
  (multiple-value-bind (form position error)
      (cl-user::parse-one-form "#.(+ 1 2)")
    (declare (ignore form position))
    (is error)))

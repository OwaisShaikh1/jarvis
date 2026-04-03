;;; Test root-cause contradiction detection with rule-derived facts

(load "load-system.lisp")
(load "main.lisp")

(format t "~&=== Testing Root-Cause Contradiction Tracing ===~%~%")

;; Reset and setup
(jarvis.knowledge:clear-databases)
(jarvis.truth-maintenance:clear-tms)

;; Add facts and rules to create contradiction scenario
(let* ((fact1 (jarvis.knowledge:store-fact (jarvis.knowledge:make-fact '(human harsh))))
       (fact2 (jarvis.knowledge:store-fact (jarvis.knowledge:make-fact '(!mortal harsh))))
       (rule1 (jarvis.knowledge:store-rule 
               (jarvis.knowledge:make-rule 'human-implies-mortal '((human ?x)) '(mortal ?x)))))
  
  (format t "[setup] Added: ~A (human harsh)~%" (jarvis.knowledge:fact-id fact1))
  (format t "[setup] Added: ~A (!mortal harsh)~%" (jarvis.knowledge:fact-id fact2))
  (format t "[setup] Added rule: human-implies-mortal~%~%")
  
  ;; Register contradiction
  (jarvis.truth-maintenance:register-contradiction (jarvis.knowledge:fact-id fact1) 
                                                   (jarvis.knowledge:fact-id fact2))
  (format t "[setup] Registered contradiction between FACT-1 and FACT-2~%")
  (format t "[setup] Contradiction will be: human(harsh) vs !mortal(harsh)~%~%")
  
  ;; Run inference (will derive mortal(harsh) from human(harsh) using the rule)
  ;; This creates a JUSTIFICATION for the derived fact
  (format t "[step] Running inference to derive mortal(harsh)...~%~%")
  (jarvis.inference:run-inference)
  
  ;; Now check contradictions — should show root-cause tracing with proof chain
  (format t "~&[step] Now checking for contradictions...~%")
  (format t "[step] Expected: show how mortal(harsh) was derived, and root cause options~%~%")
  (jarvis.truth-maintenance:check-contradictions)
  
  (format t "~&[test] Complete. Note: mortal(harsh) is derived from human(harsh) via rule,~%")
  (format t "[test] so retracting human(harsh) would cascade retract the derived mortal(harsh).~%"))



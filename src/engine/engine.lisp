(in-package :jarvis.engine)

(defun infer (&key goal (max-cycles 1000) rules quiet)
  "Run inference with trace recording and TMS justification in one path."
  (let ((previous-hook jarvis.inference:*on-rule-fired*)
        (session-id nil)
        (completed-trace nil)
        (new-facts nil))
    (labels ((run ()
               (setf session-id (jarvis.trace:begin-trace-session))
               (let ((recorder jarvis.inference:*on-rule-fired*))
                 (setf jarvis.inference:*on-rule-fired*
                       (lambda (rule bindings new-fact new-p)
                         (when (and new-p (fact-derived-p new-fact))
                           (jarvis.truth-maintenance:add-justification
                            (jarvis.knowledge:fact-id new-fact)
                            (jarvis.knowledge:rule-id rule)
                            (jarvis.trace:inputs-from-bindings rule bindings)))
                         (when recorder
                           (funcall recorder rule bindings new-fact new-p))
                         (when previous-hook
                           (funcall previous-hook rule bindings new-fact new-p)))))
               (setf new-facts
                     (jarvis.inference:run-inference
                      :goal goal :max-cycles max-cycles :rules rules))
               (setf completed-trace
                     (jarvis.trace:end-trace-session session-id))
               (values new-facts completed-trace)))
      (unwind-protect
           (if quiet
               (let ((*standard-output* (make-broadcast-stream)))
                 (run))
               (run))
        (when (and session-id (null completed-trace))
          (jarvis.trace:end-trace-session session-id))
        (setf jarvis.inference:*on-rule-fired* previous-hook)))))

(in-package :jarvis.plane.explain)

(defun %trajectory (id)
  (or (gethash id jarvis.plane.sim:*trajectories*)
      (error "Unknown trajectory ~A" id)))

(defun %summary-value (summary)
  (let ((args (jarvis.knowledge:fact-args summary)))
    (list (third args) (fourth args))))

(defun explain-trajectory (trajectory-id &optional (stream *standard-output*))
  (let ((trajectory (%trajectory trajectory-id)))
    (format stream "[explain] trajectory=~A entity=~A model=~A~%"
            (jarvis.plane.sim:trajectory-id trajectory)
            (jarvis.plane.sim:trajectory-entity trajectory)
            (jarvis.plane.sim:trajectory-model trajectory))
    (format stream "  status=~A method=~A tolerance=~,6G error-estimate=~,6G backend=~A~%"
            (jarvis.plane.sim:trajectory-status trajectory)
            (jarvis.plane.sim:trajectory-method trajectory)
            (jarvis.plane.sim:trajectory-tolerance trajectory)
            (jarvis.plane.sim:trajectory-error-estimate trajectory)
            (jarvis.plane.sim:trajectory-backend trajectory))
    (dolist (summary (jarvis.plane.sim:trajectory-summaries trajectory))
      (destructuring-bind (key value) (%summary-value summary)
        (format stream "  ~A = ~,9G [SI]~%" key value)))
    trajectory))

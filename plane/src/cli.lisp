(in-package :jarvis.plane.cli)

(defun %number (text)
  (handler-case
      (let ((*read-eval* nil))
        (multiple-value-bind (value position)
            (read-from-string text nil nil)
          (unless (and value (= position (length text)) (numberp value))
            (error "not a number"))
          (coerce value 'double-float)))
    (error () (error "Invalid number ~A" text))))

(defun %split-equals (token)
  (let ((position (position #\= token)))
    (unless position (error "Expected name=value, got ~A" token))
    (values (intern (string-upcase (subseq token 0 position))
                    :jarvis.plane.model)
            (%number (subseq token (1+ position))))))

(defun %plane-new (tokens line)
  (declare (ignore tokens line))
  (jarvis.plane.model:clear-plane)
  (clrhash jarvis.plane.sim:*trajectories*)
  (jarvis.plane.infer:clear-observations)
  (format t "[plane] new plane~%"))

(defun %add-entity (tokens line)
  (declare (ignore line))
  (if (< (length tokens) 3)
      (format t "[add-entity] Usage: add-entity <name> <type> [param=value ...]~%")
      (handler-case
          (let ((name (intern (string-upcase (second tokens)) :jarvis.plane.model))
                (type (intern (string-upcase (third tokens)) :jarvis.plane.model))
                (params nil))
            (dolist (token (cdddr tokens))
              (multiple-value-bind (key value) (%split-equals token)
                (push (list key value) params)))
            (jarvis.plane.model:add-entity name type :params (nreverse params))
            (format t "[add-entity] ~A ~A: ~A parameter(s)~%"
                    name type (length params)))
        (error (condition)
          (format t "[add-entity] ~A~%" condition)))))

(defun %simulate (tokens line)
  (declare (ignore line))
  (if (< (length tokens) 4)
      (format t "[simulate] Usage: simulate <entity> <model> <t-end> [dt]~%")
      (handler-case
          (let ((entity (intern (string-upcase (second tokens))
                                :jarvis.plane.model))
                (model (intern (string-upcase (third tokens))
                               :jarvis.plane.sim))
                (end (%number (fourth tokens)))
                (dt (if (fifth tokens) (%number (fifth tokens)) 0.01d0)))
            (multiple-value-bind (id trajectory)
                (jarvis.plane.sim:simulate entity model end dt)
              (declare (ignore trajectory))
              (format t "[simulate] ~A~%" id)))
        (error (condition)
          (format t "[simulate] ~A~%" condition)))))

(defun %laws (tokens line)
  (declare (ignore tokens line))
  (dolist (entry (sort (copy-list (jarvis.plane.laws:laws))
                       #'string< :key (lambda (item)
                                       (symbol-name (jarvis.plane.laws:law-name item)))))
    (format t "~A~:[~; (enabled)~]~% "
            (jarvis.plane.laws:law-name entry)
            (jarvis.plane.laws:law-enabled-p entry))))

(defun %observe (tokens line)
  (declare (ignore line))
  (if (< (length tokens) 4)
      (format t "[observe] Usage: observe <entity> <quantity> <value> [sigma=<n>]~%")
      (handler-case
          (let ((entity (intern (string-upcase (second tokens))
                                :jarvis.plane.model))
                (quantity (intern (string-upcase (third tokens))
                                  :jarvis.plane.laws))
                (value (%number (fourth tokens)))
                (sigma 0d0))
            (dolist (token (cddddr tokens))
              (when (search "sigma=" token :test #'char-equal)
                (setf sigma (%number (subseq token 6)))))
            (let ((observation (jarvis.plane.infer:observe
                                entity quantity value :sigma sigma)))
              (format t "[observe] ~A ~A ~A = ~A~%"
                      (jarvis.plane.infer:observation-id observation)
                      entity quantity value)))
        (error (condition) (format t "[observe] ~A~%" condition)))))

(defun %infer-params (tokens line)
  (declare (ignore line))
  (if (< (length tokens) 3)
      (format t "[infer-params] Usage: infer-params <entity> <p1> [p2 ...]~%")
      (handler-case
          (let ((entity (intern (string-upcase (second tokens))
                                :jarvis.plane.model))
                (names (mapcar (lambda (token)
                                 (intern (string-upcase token)
                                         :jarvis.plane.model))
                               (cddr tokens))))
            (format t "[infer-params] ~S~%"
                    (jarvis.plane.infer:infer-params entity names)))
        (error (condition) (format t "[infer-params] ~A~%" condition)))))

(defun %plot (tokens line)
  (declare (ignore line))
  (if (< (length tokens) 3)
      (format t "[plot] Usage: plot <trajectory-id> <file.svg|->~%")
      (handler-case
          (let ((id (intern (string-upcase (second tokens))
                            :jarvis.plane.sim))
                (path (third tokens)))
            (if (string= path "-")
                (jarvis.plane.svg:plot-ascii id)
                (jarvis.plane.svg:write-svg id path))
            (format t "[plot] ~A~%" path))
        (error (condition) (format t "[plot] ~A~%" condition)))))

(defun %algebra-backend (tokens line)
  (declare (ignore line))
  (if (< (length tokens) 2)
      (format t "[algebra-backend] Usage: algebra-backend native|maxima|crosscheck~%")
      (handler-case
          (let ((backend (intern (string-upcase (second tokens)) :keyword)))
            (setf jarvis.plane.algebra:*algebra-backend*
                  (case backend
                    (:NATIVE (make-instance 'jarvis.plane.algebra:native-backend))
                    (:MAXIMA (jarvis.plane.algebra:make-maxima-backend))
                    (:CROSSCHECK (jarvis.plane.algebra:make-crosscheck-backend))
                    (otherwise (error "Unknown backend ~A" (second tokens)))))
            (format t "[algebra-backend] ~A~%" backend))
        (error (condition) (format t "[algebra-backend] ~A~%" condition)))))

(defun %enable-law (tokens line enabled)
  (declare (ignore line))
  (if (< (length tokens) 2)
      (format t "[law] Usage: ~A <name>~%" (if enabled "enable-law" "disable-law"))
      (handler-case
          (progn
            (if enabled
                (jarvis.plane.laws:enable-law
                 (intern (string-upcase (second tokens)) :jarvis.plane.laws))
                (jarvis.plane.laws:disable-law
                 (intern (string-upcase (second tokens)) :jarvis.plane.laws)))
            (format t "[law] ~A ~A~%" (if enabled "enabled" "disabled")
                    (second tokens)))
        (error (condition) (format t "[law] ~A~%" condition)))))

(defun register-plane-commands ()
  (jarvis.cli:register-command "plane-new" #'%plane-new
                                "Clear plane state while keeping core KB.")
  (jarvis.cli:register-command "add-entity" #'%add-entity
                                "Add a plane entity and parameters.")
  (jarvis.cli:register-command "simulate" #'%simulate
                                "Run a registered simulation model.")
  (jarvis.cli:register-command "laws" #'%laws
                                "List registered physics laws.")
  (jarvis.cli:register-command "observe" #'%observe
                                "Record a numeric observation.")
  (jarvis.cli:register-command "infer-params" #'%infer-params
                                "Fit unknown entity parameters.")
  (jarvis.cli:register-command "plot" #'%plot
                                "Write a trajectory SVG or ASCII plot.")
  (jarvis.cli:register-command "algebra-backend" #'%algebra-backend
                                "Select native, Maxima, or cross-check algebra.")
  (jarvis.cli:register-command "enable-law"
                                (lambda (tokens line)
                                  (%enable-law tokens line t))
                                "Enable a physics law.")
  (jarvis.cli:register-command "disable-law"
                                (lambda (tokens line)
                                  (%enable-law tokens line nil))
                                "Disable a physics law.")
  t)

(register-plane-commands)

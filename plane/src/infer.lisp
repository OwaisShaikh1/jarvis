(in-package :jarvis.plane.infer)

(defstruct observation id entity quantity value (sigma 0d0))
(defparameter *observations* (make-hash-table :test #'eq))
(defvar *observation-sequence* 0)

(defun clear-observations ()
  (clrhash *observations*)
  (setf *observation-sequence* 0)
  nil)

(defun observe (entity quantity value &key (sigma 0d0))
  (check-type value number)
  (when (minusp sigma) (error "Observation sigma must be non-negative"))
  (let* ((id (intern (format nil "OBS-~D" (incf *observation-sequence*))
                     :jarvis.plane.infer))
         (observation (make-observation :id id :entity entity
                                        :quantity quantity
                                        :value (coerce value 'double-float)
                                        :sigma (coerce sigma 'double-float))))
    (setf (gethash id *observations*) observation)
    (let ((fact (jarvis.knowledge:make-fact
                 'observation id entity quantity value)))
      (setf (jarvis.knowledge:fact-derived-p fact) nil)
      (jarvis.knowledge:store-fact fact))
    observation))

(defun %param (entity name &optional default)
  (let ((result default))
    (maphash
     (lambda (id fact)
       (declare (ignore id))
       (let ((args (jarvis.knowledge:fact-args fact)))
         (when (and (eq (jarvis.knowledge:fact-predicate fact)
                        'jarvis.plane.model::param)
                    (equal (first args) entity)
                    (string-equal (symbol-name (second args))
                                  (symbol-name name)))
           (setf result (third args)))))
     jarvis.knowledge:*fact-db*)
    result))

(defun %bindings (entity params)
  (let ((bindings (copy-list params)))
    (dolist (name '(mass drag x0 y0 v0 angle k mu distance u a t s force
                    g r v inertia tau))
      (unless (getf bindings (intern (symbol-name name) :keyword))
        (let ((value (%param entity name)))
          (when value
            (setf (getf bindings (intern (symbol-name name) :keyword))
                  value)))))
    (unless (getf bindings :g)
      (setf (getf bindings :g) (or (%param 'world 'g) 9.81d0)))
    bindings))

(defun predict (entity quantity params)
  (let ((law (jarvis.plane.laws:law quantity)))
    (unless law
      (error "No algebraic prediction is registered for ~A" quantity))
    (coerce (jarvis.plane.laws:evaluate-law quantity
                                             (%bindings entity params))
            'double-float)))

(defun %matching-observations (entity quantities)
  (loop for observation being the hash-values of *observations*
        when (and (equal entity (observation-entity observation))
                  (member (observation-quantity observation) quantities
                          :test #'equal))
          collect observation))

(defun %current-parameters (entity names)
  (mapcar (lambda (name) (or (%param entity name) 1d0)) names))

(defun %sigma (observation)
  (max 1d-12
       (if (zerop (observation-sigma observation))
           (* 1d-9 (max 1d0 (abs (observation-value observation))))
           (observation-sigma observation))))

(defun %replace-param (entity name value)
  (let ((ids nil))
    (maphash
     (lambda (id fact)
       (declare (ignore id))
       (let ((args (jarvis.knowledge:fact-args fact)))
         (when (and (eq (jarvis.knowledge:fact-predicate fact)
                        'jarvis.plane.model::param)
                    (equal (first args) entity)
         (string-equal (symbol-name (second args))
                       (symbol-name name)))
           (push (jarvis.knowledge:fact-id fact) ids))))
     jarvis.knowledge:*fact-db*)
    (dolist (id ids) (jarvis.knowledge:retract-fact id))
    (jarvis.plane.model:set-param entity name value :status :inferred)))

(defun infer-params (entity names)
  (let* ((names (mapcar (lambda (name)
                          (if (symbolp name) name
                              (intern (string-upcase name)
                                      :jarvis.plane.model)))
                        names))
         (observations
           (loop for observation being the hash-values of *observations*
                 when (and (equal entity (observation-entity observation))
                           (jarvis.plane.laws:law
                            (observation-quantity observation)))
                   collect observation)))
    (when (< (length observations) (length names))
      (error "Not enough observations for ~A" names))
    (let* ((start (coerce (%current-parameters entity names)
                          'simple-vector))
           (fit (jarvis.plane.numerics:levenberg-marquardt
                 (lambda (p)
                   (map 'simple-vector
                        (lambda (o)
                          (let ((params nil))
                            (loop for name in names
                                  for i from 0
                                  do (setf (getf params
                                                 (intern (symbol-name name)
                                                         :keyword))
                                           (aref p i)))
                            (/ (- (predict entity (observation-quantity o)
                                            params)
                                  (observation-value o))
                               (%sigma o))))
                        observations))
                 start)))
      (dolist (name names)
        (%replace-param entity name
                        (aref (getf fit :p)
                              (position name names :test #'eq))))
      (list :entity entity :parameters names :estimates (getf fit :p)
            :status (getf fit :status) :residual-norm (sqrt (getf fit :ssr))
            :iterations (getf fit :iterations) :method :inf-lm
            :observations observations))))

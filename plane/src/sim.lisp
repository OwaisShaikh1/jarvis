(in-package :jarvis.plane.sim)

(defstruct sim-model name builder)
(defstruct trajectory id entity model times states summaries
  (status :unknown) (method :rk45) (tolerance 1d-9)
  (error-estimate 0d0) (backend :native))

(defparameter *sim-models* (make-hash-table :test #'eq))
(defparameter *trajectories* (make-hash-table :test #'eq))
(defvar *trajectory-sequence* 0)

(defun register-sim-model (name builder)
  (check-type name symbol)
  (check-type builder function)
  (setf (gethash name *sim-models*)
        (make-sim-model :name name :builder builder))
  name)

(defun %same-symbol-name-p (left right)
  "Compare symbols by name so user symbols work across package boundaries."
  (if (and (symbolp left) (symbolp right))
      (string-equal (symbol-name left) (symbol-name right))
      (equal left right)))

(defun %param (entity name &optional default)
  "Read a plane parameter without assuming its symbol package."
  (let ((result default))
    (maphash
     (lambda (id fact)
       (declare (ignore id))
       (when (and (eq (jarvis.knowledge:fact-predicate fact)
                      'jarvis.plane.model::param)
                  (%same-symbol-name-p
                   (first (jarvis.knowledge:fact-args fact)) entity)
                  (%same-symbol-name-p
                   (second (jarvis.knowledge:fact-args fact)) name))
         (setf result (third (jarvis.knowledge:fact-args fact)))))
     jarvis.knowledge:*fact-db*)
    result))

(defun %entity-param (entity name &optional default)
  (%param entity name default))

(defun %ballistic-builder (entity)
  (let* ((mass (max 1d-15 (%entity-param entity 'mass 1d0)))
         (drag (%entity-param entity 'drag 0d0))
         (g (%param 'world 'g 9.81d0))
         (x0 (%entity-param entity 'x0 0d0))
         (y0 (%entity-param entity 'y0 0d0))
         (v0 (%entity-param entity 'v0 0d0))
         (angle (%entity-param entity 'angle 0d0)))
    (list :state0 (vector x0 y0 (* v0 (cos angle)) (* v0 (sin angle)))
          :derivative
          (lambda (time state)
            (declare (ignore time))
            (vector (aref state 2) (aref state 3)
                    (- (/ (* drag (aref state 2)) mass))
                    (- g (/ (* drag (aref state 3)) mass))))
          :events
          (list (jarvis.plane.numerics:make-event
                 :name :impact
                 :fn (lambda (time state)
                       (declare (ignore time))
                       (aref state 1))
                 :direction :falling :terminal t)
                (jarvis.plane.numerics:make-event
                 :name :apex
                 :fn (lambda (time state)
                       (declare (ignore time))
                       (aref state 3))
                 :direction :falling :terminal nil)))))

(defun %spring-builder (entity)
  (let ((k (%entity-param entity 'k 1d0))
        (mass (max 1d-15 (%entity-param entity 'mass 1d0)))
        (x0 (%entity-param entity 'x0 0d0))
        (v0 (%entity-param entity 'v0 0d0)))
    (list :state0 (vector x0 v0)
          :derivative
          (lambda (time state)
            (declare (ignore time))
            (vector (aref state 1)
                    (- (* (/ k mass) (aref state 0))))))))

(defun %incline-builder (entity)
  (let ((g (%param 'world 'g 9.81d0))
        (angle (%entity-param entity 'angle 0d0))
        (mu (%entity-param entity 'mu 0d0))
        (distance (%entity-param entity 'distance)))
    (list :state0 (vector 0d0 0d0)
          :derivative
          (lambda (time state)
            (declare (ignore time))
            (vector (aref state 1)
                    (* g (- (sin angle) (* mu (cos angle))))))
          :events
          (when distance
            (list (jarvis.plane.numerics:make-event
                   :name :distance
                   :fn (lambda (time state)
                         (declare (ignore time))
                         (- (aref state 0) distance))
                   :direction :rising :terminal t))))))

(defun %store-summary (entity model key value trajectory-id)
  (declare (ignore trajectory-id))
  (let ((fact (jarvis.knowledge:make-fact
               'sim-result entity model key value)))
    (setf (jarvis.knowledge:fact-derived-p fact) t)
    (jarvis.knowledge:store-fact fact)
    fact))

(defun %event-record (events name)
  "Find the first recorded simulation event named NAME."
  (find name events :key #'first :test #'eq))

(defun %summary (entity model times states events)
  "Create summary facts from the final state and recorded events."
  (let* ((sampled-final (car (last states)))
         (impact (%event-record events :impact))
         (apex-event (%event-record events :apex))
         (last-state (if impact (third impact) sampled-final))
         (last-time (if impact (second impact) (car (last times))))
         (ys (when (= (length sampled-final) 4)
               (mapcar (lambda (state) (aref state 1)) states)))
         (apex (if apex-event
                   (aref (third apex-event) 1)
                   (when ys (apply #'max ys))))
         (apex-index (when (and ys (not apex-event))
                       (position apex ys :test #'=)))
         (apex-time (if apex-event
                        (second apex-event)
                        (when apex-index (nth apex-index times))))
         (pairs (list :final-x (aref last-state 0)
                      :final-t last-time)))
    (when (= (length last-state) 4)
      (setf pairs (append pairs
                          (list :final-y (aref last-state 1)
                                :range (aref last-state 0)
                                :apex-height apex
                                :apex-time apex-time
                                :flight-time last-time))))
    (when (= (length last-state) 2)
      (setf pairs (append pairs (list :final-s (aref last-state 0)))))
    (loop for (key value) on pairs by #'cddr
          collect (%store-summary entity model key value nil))))

(defun simulate (entity model t-end &optional (dt 0.01d0))
  (let ((descriptor (gethash model *sim-models*)))
    (unless descriptor (error "Unknown simulation model ~A" model))
    (let* ((built (funcall (sim-model-builder descriptor) entity))
           (result (multiple-value-list
                    (jarvis.plane.numerics:rk45
                     (getf built :derivative) 0d0 (getf built :state0)
                     t-end :h0 dt :events (getf built :events))))
           (times (first result))
           (states (second result))
           (status (third result))
           (metadata (fourth result))
           (id (intern (format nil "TRAJ-~D" (incf *trajectory-sequence*))
                       :jarvis.plane.sim))
           (trajectory (make-trajectory :id id :entity entity :model model
                                        :times times :states states
                                        :status status
                                        :tolerance 1d-9
                                        :error-estimate
                                        (getf metadata :max-error-estimate)
                                        :backend :native)))
      (setf (trajectory-summaries trajectory)
            (%summary entity model times states (getf metadata :events)))
      (setf (gethash id *trajectories*) trajectory)
      (values id trajectory))))

(register-sim-model :ballistic #'%ballistic-builder)
(register-sim-model :spring-1d #'%spring-builder)
(register-sim-model :incline-slide #'%incline-builder)

(jarvis.plane.model:def-entity-type
 'particle :params '(mass drag x0 y0 v0 angle))
(jarvis.plane.model:def-entity-type
 'spring :params '(k mass x0 v0))
(jarvis.plane.model:def-entity-type
 'incline :params '(angle mu distance))

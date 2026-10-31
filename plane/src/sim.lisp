(in-package :jarvis.plane.sim)

(defstruct sim-model name builder)
(defstruct trajectory id entity model times states summaries)

(defparameter *sim-models* (make-hash-table :test #'eq))
(defparameter *trajectories* (make-hash-table :test #'eq))
(defvar *trajectory-sequence* 0)

(defun register-sim-model (name builder)
  (check-type name symbol)
  (check-type builder function)
  (setf (gethash name *sim-models*)
        (make-sim-model :name name :builder builder))
  name)

(defun %param (entity name &optional default)
  (let ((result default))
    (maphash
     (lambda (id fact)
       (declare (ignore id))
       (when (and (eq (jarvis.knowledge:fact-predicate fact)
                      'jarvis.plane.model::param)
                  (equal (first (jarvis.knowledge:fact-args fact)) entity)
                  (equal (second (jarvis.knowledge:fact-args fact)) name))
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
                    (- g (/ (* drag (aref state 3)) mass)))))))

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
        (mu (%entity-param entity 'mu 0d0)))
    (list :state0 (vector 0d0 0d0)
          :derivative
          (lambda (time state)
            (declare (ignore time state))
            (vector 0d0 (* g (- (sin angle) (* mu (cos angle)))))))))

(defun %store-summary (entity model key value trajectory-id)
  (declare (ignore trajectory-id))
  (let ((fact (jarvis.knowledge:make-fact
               'sim-result entity model key value)))
    (setf (jarvis.knowledge:fact-derived-p fact) t)
    (jarvis.knowledge:store-fact fact)
    fact))

(defun %summary (entity model times states)
  (let* ((last-state (car (last states)))
         (ys (when (= (length last-state) 4)
               (mapcar (lambda (state) (aref state 1)) states)))
         (apex (when ys (apply #'max ys)))
         (apex-index (when ys (position apex ys :test #'=)))
         (pairs (list :final-x (aref last-state 0)
                      :final-t (car (last times)))))
    (when (= (length last-state) 4)
      (setf pairs (append pairs
                          (list :final-y (aref last-state 1)
                                :range (aref last-state 0)
                                :apex-height apex
                                :apex-time (nth apex-index times)
                                :flight-time (car (last times))))))
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
                     t-end :h0 dt)))
           (times (first result))
           (states (second result))
           (id (intern (format nil "TRAJ-~D" (incf *trajectory-sequence*))
                       :jarvis.plane.sim))
           (trajectory (make-trajectory :id id :entity entity :model model
                                        :times times :states states)))
      (setf (trajectory-summaries trajectory)
            (%summary entity model times states))
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

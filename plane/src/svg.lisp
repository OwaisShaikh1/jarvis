(in-package :jarvis.plane.svg)

(defun %trajectory (id)
  (or (gethash id jarvis.plane.sim:*trajectories*)
      (error "Unknown trajectory ~A" id)))

(defun %points (trajectory)
  (loop for state in (jarvis.plane.sim:trajectory-states trajectory)
        collect (list (coerce (aref state 0) 'double-float)
                      (coerce (aref state 1) 'double-float))))

(defun %range (points index)
  (let ((values (mapcar (lambda (point) (nth index point)) points)))
    (values (apply #'min values) (apply #'max values))))

(defun %scale (value low high start size)
  (if (= low high)
      (+ start (/ size 2d0))
      (+ start (* size (/ (- value low) (- high low))))))

(defun %xml-name (value)
  (with-output-to-string (stream)
    (loop for character across (string value)
          do (write-char (if (or (alphanumericp character)
                                 (member character '(#\- #\_)))
                             character #\_)
                         stream))))

(defun %nice-step (low high)
  (let* ((raw (/ (- high low) 4d0))
         (power (expt 10d0 (floor (log (max raw 1d-12) 10d0))))
         (scaled (/ raw power))
         (factor (cond ((<= scaled 1d0) 1d0)
                       ((<= scaled 2d0) 2d0)
                       ((<= scaled 5d0) 5d0)
                       (t 10d0))))
    (* factor power)))

(defun %tick-values (low high)
  (let* ((step (%nice-step low high))
         (first (* step (ceiling low step))))
    (loop for index below 5
          collect (+ first (* index step)))))

(defun %write-ticks (stream x-low x-high y-low y-high
                     x-origin y-origin width height)
  (let ((x-ticks (%tick-values x-low x-high))
        (y-ticks (%tick-values y-low y-high)))
  (dotimes (index 5)
    (let* ((x-value (nth index x-ticks))
           (y-value (nth index y-ticks))
           (x-fraction (/ (- x-value x-low) (- x-high x-low)))
           (y-fraction (/ (- y-value y-low) (- y-high y-low))))
      (format stream "  <line x1=\"~,3F\" y1=\"450\" x2=\"~,3F\" y2=\"456\" stroke=\"gray\"/>~%"
              (+ x-origin (* x-fraction width))
              (+ x-origin (* x-fraction width)))
      (format stream "  <text x=\"~,3F\" y=\"470\" font-size=\"10\">~,6G</text>~%"
              (+ x-origin (* x-fraction width)) x-value)
      (format stream "  <line x1=\"44\" y1=\"~,3F\" x2=\"50\" y2=\"~,3F\" stroke=\"gray\"/>~%"
              (- y-origin (* y-fraction height))
              (- y-origin (* y-fraction height)))
      (format stream "  <text x=\"8\" y=\"~,3F\" font-size=\"10\">~,6G</text>~%"
              (- y-origin (* y-fraction height)) y-value)))))

(defun write-svg (trajectory-id path)
  (let* ((trajectory (%trajectory trajectory-id))
         (points (%points trajectory))
         (states (jarvis.plane.sim:trajectory-states trajectory))
         (xmin 0d0) (xmax 1d0) (ymin 0d0) (ymax 1d0)
         (x-origin 50d0) (y-origin 450d0) (width 730d0) (height 430d0))
    (multiple-value-bind (raw-xmin raw-xmax) (%range points 0)
      (multiple-value-bind (raw-ymin raw-ymax) (%range points 1)
        (let ((padding-x (* 0.05d0 (max 1d0 (- raw-xmax raw-xmin))))
              (padding-y (* 0.05d0 (max 1d0 (- raw-ymax raw-ymin)))))
          (setf xmin (- raw-xmin padding-x) xmax (+ raw-xmax padding-x)
                ymin (- raw-ymin padding-y) ymax (+ raw-ymax padding-y)))))
    (with-open-file (stream path :direction :output :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
      (format stream "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"500\" viewBox=\"0 0 800 500\">~%")
      (format stream "  <title>~A ~A</title>~%"
              (%xml-name (jarvis.plane.sim:trajectory-entity trajectory))
              (%xml-name (jarvis.plane.sim:trajectory-model trajectory)))
      (format stream "  <defs><marker id=\"arrow\" markerWidth=\"6\" markerHeight=\"6\" refX=\"5\" refY=\"3\" orient=\"auto\"><path d=\"M0,0 L6,3 L0,6 z\" fill=\"green\"/></marker></defs>~%")
      (format stream "  <line x1=\"50\" y1=\"450\" x2=\"780\" y2=\"450\" stroke=\"black\"/>~%")
      (format stream "  <line x1=\"50\" y1=\"20\" x2=\"50\" y2=\"450\" stroke=\"black\"/>~%")
      (%write-ticks stream xmin xmax ymin ymax x-origin y-origin width height)
      (format stream "  <polyline fill=\"none\" stroke=\"blue\" points=\"")
      (dolist (point points)
        (format stream "~,6F,~,6F "
                (%scale (first point) xmin xmax x-origin width)
                (- y-origin (%scale (second point) ymin ymax 0d0 height))))
      (format stream "\"/>~%")
      (when (= (length (first states)) 4)
        (loop for state in states
              for index from 0
              when (= (mod index (max 1 (floor (length states) 10))) 0)
                do (format stream
                           "  <line x1=\"~,6F\" y1=\"~,6F\" x2=\"~,6F\" y2=\"~,6F\" stroke=\"green\" marker-end=\"url(#arrow)\"/>~%"
                           (%scale (aref state 0) xmin xmax x-origin width)
                           (- y-origin (%scale (aref state 1) ymin ymax 0d0 height))
                           (+ (%scale (aref state 0) xmin xmax x-origin width)
                              (* 12d0 (aref state 2)))
                           (- y-origin (%scale (aref state 1) ymin ymax 0d0 height)
                              (* 12d0 (aref state 3))))))
      (let* ((apex (position (apply #'max (mapcar #'second points))
                             points :key #'second))
             (apex-point (nth apex points))
             (impact-point (car (last points))))
        (dolist (entry (list (list "apex" apex-point)
                             (list "impact" impact-point)))
          (format stream "  <circle cx=\"~,6F\" cy=\"~,6F\" r=\"3\" fill=\"red\"/>~%"
                  (%scale (first (second entry)) xmin xmax x-origin width)
                  (- y-origin (%scale (second (second entry)) ymin ymax 0d0 height)))
          (format stream "  <text x=\"~,6F\" y=\"~,6F\" font-size=\"10\">~A (~,4F, ~,4F)</text>~%"
                  (%scale (first (second entry)) xmin xmax x-origin width)
                  (- y-origin (%scale (second (second entry)) ymin ymax 0d0 height) 8d0)
                  (first entry) (first (second entry)) (second (second entry)))))
      (format stream "</svg>~%")))
  path)

(defun plot-ascii (trajectory-id &optional (stream *standard-output*))
  (let* ((trajectory (%trajectory trajectory-id))
         (points (%points trajectory))
         (grid (make-array '(20 60) :initial-element #\Space)))
    (multiple-value-bind (xmin xmax) (%range points 0)
      (multiple-value-bind (ymin ymax) (%range points 1)
        (dolist (point points)
          (let ((x (min 59 (max 0 (round (%scale (first point) xmin xmax 0d0 59d0)))))
                (y (min 19 (max 0 (round (%scale (second point) ymin ymax 0d0 19d0))))))
            (setf (aref grid (- 19 y) x) #\*)))))
    (dotimes (row 20)
      (write-line (coerce (row-major-aref grid row) 'string) stream)))
  nil)

(require :asdf)
(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(multiple-value-bind (value dimension)
    (jarvis.plane.units:parse-quantity "9.81 m/s^2")
  (assert (< (abs (- value 9.81d0)) 1d-9))
  (assert (equal dimension '(1 0 -2 0 0))))

(let ((frame (jarvis.plane.model:make-frame
              'test-frame :ox 1d0 :oy 2d0 :rotation (/ pi 2))))
  (multiple-value-bind (x y)
      (jarvis.plane.model:frame->world frame 1d0 0d0)
    (assert (< (abs (- x 1d0)) 1d-9))
    (assert (< (abs (- y 3d0)) 1d-9))))

(assert (= (jarvis.plane.expr:evaluate '(+ x (* 2 y))
                                        '((x . 3) (y . 4)))
           11))
(format t "jarvis-plane foundation smoke tests passed.~%")
(quit)

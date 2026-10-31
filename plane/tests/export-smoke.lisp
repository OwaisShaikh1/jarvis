(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(jarvis.plane.model:clear-plane)
(jarvis.plane.model:add-entity 'ball 'particle
                               :params '((mass 1d0) (v0 10d0)
                                         (angle 0.7853981633974483d0)))
(multiple-value-bind (id trajectory)
    (jarvis.plane.sim:simulate 'ball :ballistic 1d0 0.05d0)
  (declare (ignore trajectory))
  (let ((json (merge-pathnames "plane-test.json" (truename ".")))
        (csv (merge-pathnames "plane-test.csv" (truename "."))))
    (jarvis.plane.export:write-json id json)
    (jarvis.plane.export:write-csv id csv)
    (with-open-file (stream json)
      (let ((contents (make-string (file-length stream))))
        (read-sequence contents stream)
        (assert (char= (char contents 0) #\{))
        (assert (search "\"samples\"" contents))
        (assert (search "\"summaries\"" contents))))
    (with-open-file (stream csv)
      (assert (string= "t,x,y,vx,vy" (read-line stream)))
      (assert (search "," (read-line stream))))
    (delete-file json)
    (delete-file csv)))
(format t "jarvis-plane export smoke tests passed.~%")
(quit)

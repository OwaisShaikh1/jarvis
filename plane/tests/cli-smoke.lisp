(load (merge-pathnames "../../load-system.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(load (merge-pathnames "../jarvis-plane.asd"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))
(asdf:load-system :jarvis-plane)

(jarvis.plane.model:def-entity-type 'particle
  :params '(mass drag x0 y0 v0 angle))
(assert (null (jarvis.cli:jarvis-cli-handle-command "plane-new")))
(assert (null (jarvis.cli:jarvis-cli-handle-command
               "add-entity ball particle mass=1 v0=10 angle=0.7853981633974483")))
(assert (= (hash-table-count jarvis.plane.model:*entity-registry*) 1))
(assert (null (jarvis.cli:jarvis-cli-handle-command
               "laws")))
(assert (null (jarvis.cli:jarvis-cli-handle-command
               "enable-law spring-period")))
(assert (null (jarvis.cli:jarvis-cli-handle-command
               "observe ball spring-period 1.4 sigma=0.01")))
(assert (null (jarvis.cli:jarvis-cli-handle-command
               "infer-params ball k")))
(assert (jarvis.plane.laws:law-enabled-p
         (jarvis.plane.laws:law 'spring-period)))
(format t "jarvis-plane CLI smoke tests passed.~%")
(quit)

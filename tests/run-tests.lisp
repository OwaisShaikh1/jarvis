(require :asdf)
(ql:quickload :fiveam)

(defparameter cl-user::*jarvis-root*
  (make-pathname :name nil :type nil :version nil :defaults
                 (or *load-truename* *default-pathname-defaults*)))
(pushnew cl-user::*jarvis-root* asdf:*central-registry* :test #'equal)

(asdf:load-system "jarvis")
(load (merge-pathnames "main.lisp" cl-user::*jarvis-root*))
(asdf:load-asd (merge-pathnames "tests/jarvis-tests.asd"
                                cl-user::*jarvis-root*))
(asdf:load-system "jarvis-tests")

(let ((result (fiveam:run! 'jarvis.tests::jarvis-suite)))
  (unless (fiveam:results-status result)
    (sb-ext:exit :code 1)))

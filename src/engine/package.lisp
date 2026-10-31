(defpackage :jarvis.engine
  (:use :cl)
  (:import-from :jarvis.knowledge
                #:fact-derived-p)
  (:export #:infer))

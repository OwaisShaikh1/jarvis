(defpackage :jarvis.plane.numeric
  (:use :cl)
  (:export #:numeric-policy #:make-numeric-policy #:numbers-match-p
           #:set-policy #:effective-policy #:*policies*
           #:install-term-equality-hook))

(defpackage :jarvis.plane.units
  (:use :cl)
  (:export #:quantity #:make-quantity #:quantity-value #:quantity-dimension
           #:parse-quantity #:format-quantity #:dim* #:dim/ #:dim-expt #:dim=))

(defpackage :jarvis.plane.expr
  (:use :cl)
  (:export #:evaluate #:expr-dimension #:eval-error #:dimension-mismatch
           #:inexact-in-rational-domain))

(defpackage :jarvis.plane.model
  (:use :cl)
  (:export #:frame #:make-frame #:frame->world #:world->frame #:*world-frame*
           #:add-point #:add-vector #:add-line #:add-segment #:add-circle
           #:add-polygon #:add-curve #:add-entity #:set-param
           #:def-param-kind #:declare-predicate-dims #:def-entity-type
           #:*entity-registry* #:*param-kinds* #:*entity-types*
           #:clear-plane))

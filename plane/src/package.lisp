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

(defpackage :jarvis.plane.algebra
  (:use :cl)
  (:export #:alg-simplify #:alg-substitute #:alg-diff #:alg-solve
           #:alg-evaluate #:alg-capabilities #:to-canonical
           #:native-backend #:maxima-backend #:crosscheck-backend
           #:make-maxima-backend #:make-crosscheck-backend
           #:maxima-available-p #:*algebra-backend* #:with-backend
           #:cannot-solve #:backend-unavailable))

(defpackage :jarvis.plane.numerics
  (:use :cl)
  (:export #:rk4 #:rk45 #:event #:make-event
           #:newton-solve #:levenberg-marquardt))

(defpackage :jarvis.plane.sim
  (:use :cl)
  (:export #:sim-model #:register-sim-model #:simulate
           #:*sim-models* #:*trajectories* #:trajectory #:trajectory-p
           #:trajectory-id #:trajectory-entity #:trajectory-model
           #:trajectory-times #:trajectory-states #:trajectory-summaries
           #:trajectory-status #:trajectory-method #:trajectory-tolerance
           #:trajectory-error-estimate #:trajectory-backend))

(defpackage :jarvis.plane.laws
  (:use :cl)
  (:export #:law #:law-name #:enable-law #:disable-law #:laws
           #:law-enabled-p #:*law-registry* #:apply-enabled-laws
           #:evaluate-law))

(defpackage :jarvis.plane.infer
  (:use :cl)
  (:export #:observation #:observe #:clear-observations #:*observations* #:predict
           #:infer-params #:observation-id #:observation-entity #:observation-quantity
           #:observation-value #:observation-sigma))

(defpackage :jarvis.plane.svg
  (:use :cl)
  (:export #:write-svg #:plot-ascii))

(defpackage :jarvis.plane.export
  (:use :cl)
  (:export #:write-json #:write-csv #:export-trajectory))

(defpackage :jarvis.plane.explain
  (:use :cl)
  (:export #:explain-trajectory))

(defpackage :jarvis.plane.cli
  (:use :cl)
  (:export #:register-plane-commands))

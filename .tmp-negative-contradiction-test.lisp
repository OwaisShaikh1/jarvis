(load "main.lisp")
(jarvis.knowledge:clear-databases)
(jarvis.truth-maintenance:clear-tms)
(jarvis.trace:clear-traces)

(jarvis-cli-handle-command "add-fact (alive plato)")
(jarvis-cli-handle-command "add-fact (dead plato)")
(jarvis-cli-handle-command "add-rule alive-implies-!dead ((alive ?x)) (!dead ?x)")
(jarvis-cli-handle-command "infer")
(jarvis-cli-handle-command "facts")

(quit)

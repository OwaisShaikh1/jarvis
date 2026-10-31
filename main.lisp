(in-package :cl-user)

(defun main ()
  "Run the Jarvis demonstration through the CLI package."
  (jarvis.cli:main))

(defun jarvis-cli ()
  "Start the Jarvis interactive CLI through the CLI package."
  (jarvis.cli:jarvis-cli))

(defun jarvis-cli-handle-command (line)
  "Handle one Jarvis CLI command line through the CLI package."
  (jarvis.cli:jarvis-cli-handle-command line))

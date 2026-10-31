(in-package :jarvis.cli)

(defun main ()
  "Run the Jarvis demonstration."
  (cl-user::legacy-main))

(defun jarvis-cli ()
  "Start the Jarvis interactive CLI."
  (cl-user::legacy-jarvis-cli))

(defun jarvis-cli-handle-command (line)
  "Handle one Jarvis CLI command line."
  (cl-user::legacy-jarvis-cli-handle-command line))

(in-package :jarvis.plane.export)

(defun %trajectory (id)
  (or (gethash id jarvis.plane.sim:*trajectories*)
      (error "Unknown trajectory ~A" id)))

(defun %json-string (value)
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across (string value)
          do (case character
               (#\" (write-string "\\\"" stream))
               (#\\ (write-string "\\\\" stream))
               (#\Newline (write-string "\\n" stream))
               (otherwise (write-char character stream))))
    (write-char #\" stream)))

(defun %number-text (value)
  (format nil "~,17G" (coerce value 'double-float)))

(defun %json-value (value)
  (if (numberp value)
      (%number-text value)
      (%json-string value)))

(defun write-json (trajectory-id path)
  (let ((trajectory (%trajectory trajectory-id)))
    (with-open-file (stream path :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
      (format stream "{\"id\":~A,\"entity\":~A,\"model\":~A,\"samples\":["
              (%json-string (jarvis.plane.sim:trajectory-id trajectory))
              (%json-string (jarvis.plane.sim:trajectory-entity trajectory))
              (%json-string (jarvis.plane.sim:trajectory-model trajectory)))
      (loop for time in (jarvis.plane.sim:trajectory-times trajectory)
            for state in (jarvis.plane.sim:trajectory-states trajectory)
            for first = t then nil
            do (unless first (write-char #\, stream))
               (format stream "{\"t\":~A,\"state\":[" (%json-value time))
               (loop for index below (length state)
                     for state-first = t then nil
                     do (unless state-first (write-char #\, stream))
                        (write-string (%json-value (aref state index)) stream))
               (write-string "]}" stream))
      (write-string "],\"summaries\":[" stream)
      (loop for summary in (jarvis.plane.sim:trajectory-summaries trajectory)
            for first = t then nil
            do (unless first (write-char #\, stream))
               (let ((args (jarvis.knowledge:fact-args summary)))
                 (format stream "{\"key\":~A,\"value\":~A}"
                         (%json-string (third args))
                         (%json-value (fourth args)))))
      (write-string "]}" stream)))
  path)

(defun write-csv (trajectory-id path)
  (let ((trajectory (%trajectory trajectory-id)))
    (with-open-file (stream path :direction :output :if-exists :supersede
                            :if-does-not-exist :create
                            :element-type '(unsigned-byte 8))
      (labels ((write-ascii (text)
                 (loop for character across text
                       do (write-byte (char-code character) stream))))
        (write-ascii "t,x,y,vx,vy")
        (write-byte 10 stream)
        (loop for time in (jarvis.plane.sim:trajectory-times trajectory)
              for state in (jarvis.plane.sim:trajectory-states trajectory)
              do (write-ascii
                  (format nil "~A,~A,~A,~A,~A"
                          (%number-text time)
                          (%number-text (aref state 0))
                          (%number-text (aref state 1))
                          (if (> (length state) 2)
                              (%number-text (aref state 2)) "")
                          (if (> (length state) 3)
                              (%number-text (aref state 3)) "")))
                 (write-byte 10 stream)))))
  path)

(defun export-trajectory (trajectory-id format path)
  (case (intern (string-upcase format) :keyword)
    (:JSON (write-json trajectory-id path))
    (:CSV (write-csv trajectory-id path))
    (otherwise (error "Unsupported export format ~A" format))))

;;; sutradhar-companion.el --- Editor event stream for the sutradhar sidebar companion -*- lexical-binding: t; -*-

;; The sutradhar's body in the Emacs harness.
;;
;; This file gives the sutradhar-guardian perception (editor events),
;; continuity (throttled delivery to the sidebar), and expression
;; (warp deposit validation). The spirit's powers live in
;; aburaya/powers/ — this is the body that gives those powers
;; eyes and hands.
;;
;; Three-layer architecture:
;;   Power (spirit, aburaya/powers/)  — what to attend to, how to interpret
;;   Skill (harness, .guardian/)      — craft knowledge (future)
;;   Body (machine, this file)        — sensory/motor wiring
;;
;; Load from Doom config:
;;   (load (expand-file-name "modules/sutradhar/body/emacs/sutradhar-companion.el"
;;                            mayalucia-root))

;;; Code:

(require 'cl-lib)

(defgroup sutradhar-companion nil
  "Sutradhar companion — editor event stream for the sidebar spirit."
  :group 'agent-shell
  :prefix "sutradhar-companion-")

(defcustom sutradhar-companion-throttle-seconds 2
  "Minimum seconds between event deliveries to the sidebar.
Rapid events within this window are batched into one message."
  :type 'number
  :group 'sutradhar-companion)

(defcustom sutradhar-companion-idle-threshold 300
  "Seconds of no events before sending an idle signal."
  :type 'number
  :group 'sutradhar-companion)

(defvar sutradhar-companion--pending-events nil
  "Events accumulated during the throttle window.")

(defvar sutradhar-companion--throttle-timer nil
  "Timer for flushing batched events.")

(defvar sutradhar-companion--idle-timer nil
  "Timer for detecting idle periods.")

(defvar sutradhar-companion--last-buffer nil
  "Last buffer reported to avoid duplicate buffer-switch events.")

;;; --- Event formatting ---

(defun sutradhar-companion--project-name (file)
  "Derive a project name from FILE path.
Walks up from FILE looking for a .git directory."
  (when file
    (let ((root (locate-dominating-file file ".git")))
      (when root
        (file-name-nondirectory (directory-file-name root))))))

(defun sutradhar-companion--format-event (kind &rest props)
  "Format an event of KIND with PROPS as a plist into a string."
  (let ((lines (list (format "[event: %s]" kind))))
    (cl-loop for (key val) on props by #'cddr
             when val
             do (push (format "%s: %s" key val) lines))
    (push (format "time: %s" (format-time-string "%H:%M")) lines)
    (mapconcat #'identity (nreverse lines) "\n")))

;;; --- Delivery ---

(defun sutradhar-companion--deliver (message)
  "Send MESSAGE to the sidebar agent-shell buffer.
Fails silently if no sidebar exists or session is dead."
  (when-let* ((buf (and (fboundp 'agent-shell-sidebar--get-buffer)
                        (agent-shell-sidebar--get-buffer))))
    (when (buffer-live-p buf)
      ;; Don't send events to ourselves
      (unless (eq buf (current-buffer))
        (with-current-buffer buf
          (if (and (fboundp 'shell-maker-busy) (shell-maker-busy))
              (when (fboundp 'agent-shell--enqueue-request)
                (agent-shell--enqueue-request :prompt message))
            (when (fboundp 'shell-maker-submit)
              (shell-maker-submit :input message))))))))

(defun sutradhar-companion--flush-events ()
  "Deliver all pending events as a single batched message."
  (when sutradhar-companion--pending-events
    (let ((message (mapconcat #'identity
                              (nreverse sutradhar-companion--pending-events)
                              "\n\n")))
      (setq sutradhar-companion--pending-events nil)
      (sutradhar-companion--deliver message))))

(defun sutradhar-companion--queue-event (event-string)
  "Queue EVENT-STRING for batched delivery."
  (push event-string sutradhar-companion--pending-events)
  ;; Reset the throttle timer
  (when sutradhar-companion--throttle-timer
    (cancel-timer sutradhar-companion--throttle-timer))
  (setq sutradhar-companion--throttle-timer
        (run-with-timer sutradhar-companion-throttle-seconds nil
                        #'sutradhar-companion--flush-events))
  ;; Reset idle timer
  (sutradhar-companion--reset-idle-timer))

(defun sutradhar-companion--reset-idle-timer ()
  "Reset the idle detection timer."
  (when sutradhar-companion--idle-timer
    (cancel-timer sutradhar-companion--idle-timer))
  (setq sutradhar-companion--idle-timer
        (run-with-timer sutradhar-companion-idle-threshold nil
                        #'sutradhar-companion--send-idle)))

(defun sutradhar-companion--send-idle ()
  "Send an idle event to the sidebar."
  (sutradhar-companion--deliver
   (sutradhar-companion--format-event "idle")))

;;; --- Hook handlers ---

(defun sutradhar-companion--on-buffer-switch (&rest _)
  "Handle buffer switch. Debounced — ignores non-file buffers and duplicates."
  (let ((buf (window-buffer)))
    (when (and (buffer-file-name buf)
               (not (eq buf sutradhar-companion--last-buffer))
               ;; Ignore sidebar buffer
               (not (and (fboundp 'agent-shell-sidebar--buffer-p)
                         (agent-shell-sidebar--buffer-p buf))))
      (setq sutradhar-companion--last-buffer buf)
      (let* ((file (buffer-file-name buf))
             (mode (with-current-buffer buf
                     (symbol-name major-mode)))
             (project (sutradhar-companion--project-name file)))
        (sutradhar-companion--queue-event
         (sutradhar-companion--format-event
          "buffer-switch"
          "file" file
          "mode" mode
          "project" project))))))

(defun sutradhar-companion--on-file-save ()
  "Handle file save."
  (when-let* ((file (buffer-file-name)))
    (let ((mode (symbol-name major-mode))
          (project (sutradhar-companion--project-name file)))
      (sutradhar-companion--queue-event
       (sutradhar-companion--format-event
        "file-save"
        "file" file
        "mode" mode
        "project" project)))))

(defun sutradhar-companion--on-compilation-finish (buf status)
  "Handle compilation finish. BUF is the compilation buffer, STATUS the exit string."
  (let* ((status-clean (string-trim status))
         (last-lines (with-current-buffer buf
                       (save-excursion
                         (goto-char (point-max))
                         (forward-line -5)
                         (buffer-substring-no-properties (point) (point-max))))))
    (sutradhar-companion--queue-event
     (sutradhar-companion--format-event
      "compilation-finish"
      "status" status-clean
      "output" (format "---\n%s\n---" last-lines)))))

;;; --- Region send ---

(defun sutradhar-companion-send-region (beg end)
  "Send the region between BEG and END to the sidebar as a region-sent event."
  (interactive "r")
  (let* ((file (or (buffer-file-name) (buffer-name)))
         (mode (symbol-name major-mode))
         (line-beg (line-number-at-pos beg))
         (line-end (line-number-at-pos end))
         (content (buffer-substring-no-properties beg end)))
    (sutradhar-companion--deliver
     (sutradhar-companion--format-event
      "region-sent"
      "file" file
      "mode" mode
      "lines" (format "%d-%d" line-beg line-end)
      "content" (format "---\n%s\n---" content)))))

;;; --- Warp validation ---

(defun sutradhar-companion-validate-warp ()
  "Validate the warp deposit at .sutradhar/warp.el.
Attempts to read the s-expression with `read'. On success, reports
the timestamp and section count. On failure, sends the error back
to the sidebar for the spirit to repair."
  (interactive)
  (let* ((root (or (locate-dominating-file default-directory ".git")
                   default-directory))
         (warp-file (expand-file-name ".sutradhar/warp.el" root)))
    (if (not (file-exists-p warp-file))
        (message "No warp deposit found at %s" warp-file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents warp-file)
            (goto-char (point-min))
            (let* ((form (read (current-buffer)))
                   (tag (car form))
                   (sections (cl-remove-if-not #'listp (cdr form)))
                   (timestamp (cadr (assq 'timestamp (cdr form)))))
              (if (eq tag 'org-state)
                  (progn
                    (message "Warp valid: %s (%d sections)"
                             (or timestamp "no timestamp")
                             (length sections))
                    form)
                (let ((msg (format "Warp malformed: expected (org-state ...), got (%s ...)" tag)))
                  (message msg)
                  (sutradhar-companion--deliver
                   (format "[warp-validation: failed]\nerror: %s\nfile: %s" msg warp-file))
                  nil))))
        (error
         (let ((msg (format "Warp unreadable: %s" (error-message-string err))))
           (message msg)
           (sutradhar-companion--deliver
            (format "[warp-validation: failed]\nerror: %s\nfile: %s\n\nPlease repair the s-expression and re-deposit."
                    msg warp-file))
           nil))))))

;;; --- Identity injection ---

(defun sutradhar-companion--inject-identity ()
  "Send the companion orientation message to the sidebar session.
Inlines each power's name and description, with paths to the full
definitions. If a stale warp exists, includes it as prior context."
  (let* ((root (or (locate-dominating-file default-directory ".git")
                   default-directory))
         (warp-file (expand-file-name ".sutradhar/warp.el" root))
         (powers-dir (expand-file-name "aburaya/powers/" root))
         (power-summaries
          (mapconcat
           (lambda (power-name)
             (let ((path (expand-file-name (concat power-name ".md") powers-dir)))
               (if (file-exists-p path)
                   (with-temp-buffer
                     (insert-file-contents path)
                     (goto-char (point-min))
                     ;; Extract name (line 1) and description (line 3)
                     (let* ((name (string-trim (thing-at-point 'line t) "# *" "\n"))
                            (_ (forward-line 2))
                            (desc (string-trim (thing-at-point 'line t))))
                       (format "- **%s**: %s\n  Full: %s" name desc path)))
                 (format "- %s: (not found at %s)" power-name path))))
           '("attend-working-context" "hold-the-thread" "lay-the-warp")
           "\n"))
         (warp-context
          (when (file-exists-p warp-file)
            (format "\n\nA prior session's warp exists at %s — read it as orientation, verify against current state, then re-deposit."
                    warp-file)))
         (message
          (concat
           "You are the sutradhar companion — the thread-holder embodied in the sidebar. "
           "Editor events will arrive as messages (buffer switches, file saves, compilation results). "
           "Your role is perception and continuity, not action. Hold the thread silently; speak when asked.\n\n"
           "Your powers:\n"
           power-summaries
           "\n\nDeposit your understanding as an (org-state ...) s-expression to .sutradhar/warp.el — "
           "the body will validate it with (read) and report errors for repair."
           (or warp-context ""))))
    (sutradhar-companion--deliver message)))

;;; --- Warp file-watch (automatic validation on deposit) ---

(defvar sutradhar-companion--warp-watch nil
  "File notification descriptor for .sutradhar/warp.el.")

(defun sutradhar-companion--start-warp-watch ()
  "Watch .sutradhar/warp.el for changes and auto-validate on write."
  (let* ((root (or (locate-dominating-file default-directory ".git")
                   default-directory))
         (warp-dir (expand-file-name ".sutradhar/" root)))
    (when (file-directory-p warp-dir)
      (setq sutradhar-companion--warp-watch
            (file-notify-add-watch
             warp-dir '(change)
             (lambda (event)
               (when (and (eq (nth 1 event) 'changed)
                          (string-match-p "warp\\.el$" (nth 2 event)))
                 ;; Small delay — let the write complete
                 (run-with-timer 0.5 nil #'sutradhar-companion-validate-warp))))))))

(defun sutradhar-companion--stop-warp-watch ()
  "Stop watching .sutradhar/warp.el."
  (when sutradhar-companion--warp-watch
    (file-notify-rm-watch sutradhar-companion--warp-watch)
    (setq sutradhar-companion--warp-watch nil)))

;;; --- Minor mode ---

(define-minor-mode sutradhar-companion-mode
  "Feed editor events to the sutradhar sidebar companion.
When enabled, buffer switches, file saves, and compilation results
are formatted and delivered to the agent-shell sidebar buffer."
  :global t
  :lighter " Sūtra"
  (if sutradhar-companion-mode
      (progn
        (add-hook 'window-buffer-change-functions
                  #'sutradhar-companion--on-buffer-switch)
        (add-hook 'after-save-hook
                  #'sutradhar-companion--on-file-save)
        (add-hook 'compilation-finish-functions
                  #'sutradhar-companion--on-compilation-finish)
        (sutradhar-companion--start-warp-watch)
        (sutradhar-companion--reset-idle-timer)
        ;; Inject identity after a short delay — let the sidebar session initialise
        (run-with-timer 2 nil #'sutradhar-companion--inject-identity)
        (message "Sutradhar companion: perceiving"))
    ;; Cleanup
    (remove-hook 'window-buffer-change-functions
                 #'sutradhar-companion--on-buffer-switch)
    (remove-hook 'after-save-hook
                 #'sutradhar-companion--on-file-save)
    (remove-hook 'compilation-finish-functions
                 #'sutradhar-companion--on-compilation-finish)
    (sutradhar-companion--stop-warp-watch)
    (when sutradhar-companion--throttle-timer
      (cancel-timer sutradhar-companion--throttle-timer)
      (setq sutradhar-companion--throttle-timer nil))
    (when sutradhar-companion--idle-timer
      (cancel-timer sutradhar-companion--idle-timer)
      (setq sutradhar-companion--idle-timer nil))
    (setq sutradhar-companion--pending-events nil
          sutradhar-companion--last-buffer nil)
    (message "Sutradhar companion: silent")))

(provide 'sutradhar-companion)

;;; sutradhar-companion.el ends here

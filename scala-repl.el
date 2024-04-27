;;; scala-repl.el --- Scala REPL Mode      -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Daian YUE

;; Author: Daian YUE <sheepduke@gmail.com>
;; Version: 0.1.0
;; Filename: scala-repl.el
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages, tools
;; URL: https://github.com/sheepduke/scala-repl.el

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides functions to perform REPL-driven development
;; for Scala programming language.
;;
;; Currently it supports the following features:
;;
;; 1. Automatically detect project root, trigger a REPL session and
;;    attach to it.
;; 
;; 2. Evaluate source code in the REPL session that the current buffer
;;    is attached to.
;; 
;; 3. Customize commands to run for SBT/Mill projects or non-project
;;    files.
;; 
;; 4. Run ad-hoc REPL sessions with custom commands and manually
;;    attach to/detach from it.
;; 
;; 5. Support multiple REPL sessions for different projects/ad-hoc
;;    files.
;;
;; Note that the evaluation functionality is restricted by
;; corresponding Scala REPL.
;;
;; Also note that this package *might* work on Emacs < 29.1, but it is
;; not guaranteed.  You are welcome to open an issue on the GitHub page
;; and let know if it does.
;;
;; This package does not define any minor mode.  You are free to bind
;; its functions in scala-mode or scala-ts-mode however you like.

;;; Code:

(require 'comint)
(require 'cl-lib)

(defgroup scala-repl nil
  "Group for Scala REPL."
  :group 'scala)

(defcustom scala-repl-buffer-basename "Scala REPL"
  "Buffer name for Scala REPL process."
  :type 'string
  :group 'scala-repl)

(defcustom scala-repl-command-alist
  '((mill "mill" "-i" "_.console")
    (sbt "sbt" "console")
    (nil "scala-cli" "repl" "-deprecation"))
  "The alist of REPL commands."
  :group 'scala-repl
  :type 'alist)

(defvar-local scala-repl-buffer-name nil
  "The buffer name of REPL process.")

(defvar-local scala-repl-project-type-root nil
  "A cons of project type and root directory.")

(defun scala-repl-run (&optional prefix)
  "Run the REPL and show it in a new window.
If PREFIX is given, run a custom command."
  (interactive "P")
  (scala-repl--detach)
  (if (and prefix (> (car prefix) 0))
      (call-interactively #'scala-repl-run-custom)
    (scala-repl--ensure-session-buffer))
  (message "REPL running. Happy hacking"))

(defun scala-repl-run-custom (&optional command)
  "Just run the REPL with custom COMMAND under current directory."
  (interactive "MREPL command: ")
  (let* ((command (string-trim command))
         (space-position (cl-position ?\s command))
         (program (if space-position
                      (substring command 0 space-position)
                    command))
         (switches (if space-position
                       (split-string-and-unquote (substring command (1+ space-position)))
                     nil))
         (buffer-name (format "*%s*" (file-name-nondirectory program))))
    (apply #'make-comint-in-buffer buffer-name buffer-name program nil switches)
    (switch-to-buffer-other-window buffer-name)))

(defun scala-repl-attach (&optional buffer-name)
  "Attach current buffer (or with BUFFER-NAME) to the REPL."
  (interactive "bChoose REPL Buffer:")
  (setq-local scala-repl-buffer-name buffer-name)
  (message "REPL %s attached" buffer-name))

(defun scala-repl-detach ()
  "Detach current buffer from any REPL buffer."
  (interactive)
  (scala-repl--detach)
  (message "REPL detached"))

(defun scala-repl-restart ()
  "Restart the REPL session."
  (interactive)
  (save-excursion
    (let* ((buffer-name (scala-repl--ensure-session-buffer t))
           (process (get-buffer-process buffer-name)))
      (while (process-live-p process)
        (kill-process process)))
    (message "Restarting REPL...")
    (scala-repl--ensure-session-buffer nil)
    (with-current-buffer (buffer-name)
      (goto-char (point-max)))))

(defun scala-repl-clear ()
  "Clear the REPL buffer."
  (interactive)
  (let* ((buffer-name (scala-repl--ensure-session-buffer)))
    (with-current-buffer buffer-name
      (comint-clear-buffer))))

(defun scala-repl-save-and-load ()
  "Load the file corresponding to current buffer."
  (interactive)
  (save-buffer)
  (if (scala-repl--ensure-project-root)
      (message "Not implemented yet.")
    (scala-repl-eval-raw-string (format ":load %s\n" (buffer-name)))))

(defun scala-repl-load-file (&optional file-name)
  "Load the file of FILE-NAME into REPL using `:load' command."
  (interactive "MLoad file: ")
  (scala-repl-eval-raw-string (format ":load %s\n" file-name)))

(defun scala-repl-eval-region-or-line ()
  "Evaluate the selected region when a region is active.
Otherwise, evaluate current line."
  (interactive)
  (if (region-active-p)
      (scala-repl-eval-region)
    (scala-repl-eval-current-line)))

(defun scala-repl-eval-current-line ()
  "Send current line to the REPL and evaluate it."
  (interactive)
  (scala-repl-eval-string (thing-at-point 'line)))

(defun scala-repl-eval-buffer ()
  "Send current buffer to the REPL and evaluate it."
  (interactive)
  (scala-repl-eval-string (buffer-string)))

(defun scala-repl-eval-region ()
  "Send selected region to the REPL and evaluate it."
  (interactive)
  (if (region-active-p)
      (progn
        (scala-repl--ensure-session-buffer)
        (scala-repl-eval-string (buffer-substring (region-beginning)
                                                  (region-end))))
    (message "Region not active")))

(defun scala-repl--ensure-session-buffer (&optional no-switch-p)
  "Ensure the session buffer is created."
  (if (and scala-repl-buffer-name
           (process-live-p (get-buffer-process scala-repl-buffer-name)))
      scala-repl-buffer-name
    (let* ((project-type-root (scala-repl--ensure-project-root))
           (project-type (car project-type-root))
           (project-root (or (cdr project-type-root)
                             (expand-file-name ".")))
           (buffer-name (scala-repl--get-buffer-name project-type project-root))
           (command (scala-repl--get-command project-type)))
      (let ((default-directory project-root))
        (apply #'make-comint-in-buffer buffer-name buffer-name (car command) nil (cdr command)))
      (unless no-switch-p
        (switch-to-buffer-other-window buffer-name))
      buffer-name)))

(defun scala-repl-eval-string (&optional string)
  "Quote given STRING in braces, send it to the REPL and evaluate it."
  (interactive "MEval: ")
  (save-excursion
    (let* ((buffer-name (scala-repl--ensure-session-buffer)))
      (comint-send-string buffer-name (format "{\n%s}\n" string)))))

(defun scala-repl-eval-raw-string (&optional string)
  "Send given raw STRING to the REPL and evaluate it."
  (interactive "MEval: ")
  (save-excursion
    (let* ((buffer-name (scala-repl--ensure-session-buffer)))
      (comint-send-string buffer-name string))))

(defun scala-repl--get-buffer-name (project-type project-root)
  "Get the name of REPL buffer.
PROJECT-TYPE is a symbol indicating the type of project.
PROJECT-ROOT is the root of project."
  (unless scala-repl-buffer-name
    (setq-local scala-repl-buffer-name
                (if project-type
                    (format "*%s - %s*"
                            scala-repl-buffer-basename
                            (file-name-nondirectory project-root))
                  (format "*%s*" scala-repl-buffer-basename))))

  scala-repl-buffer-name)

(defun scala-repl--detach ()
  "Detach current buffer."
  (setq-local scala-repl-buffer-name nil))

(defun scala-repl--get-command (project-type)
  "Get the command (according to PROJECT-TYPE) to start the REPL."
  (cdr (assoc project-type scala-repl-command-alist)))

(defun scala-repl--ensure-project-root ()
  "Read the cached project root, or determine and cache it."
  (unless scala-repl-project-type-root
    (setq-local scala-repl-project-type-root
                (scala-repl--locate-project-root ".")))
  scala-repl-project-type-root)

(defun scala-repl--locate-project-root (directory)
  "Locate project root of given DIRECTORY."
  (let ((directory (expand-file-name directory)))
    (if (string= directory "/")
        nil
      (cond
       ((directory-files (expand-file-name directory) t "build.sc") (cons 'mill directory))
       ((directory-files (expand-file-name directory) t "build.sbt") (cons 'sbt directory))
       ((directory-files (expand-file-name directory) t "project.scala") (cons 'scala-cli directory))
       (t (scala-repl--locate-project-root (expand-file-name (format "%s/.." directory))))))))

(provide 'scala-repl)
;;; scala-repl.el ends here

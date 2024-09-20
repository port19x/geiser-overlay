;;; geiser-overlay.el --- Overlay Scheme evaluation results -*- lexical-binding: t; -*-
;;
;; Copyright (C) port19
;;
;; Author: port19 <port19@port19.xyz>
;; Version: 1.1.0
;; Package-Requires: ((emacs "24.4") (geiser "0.31"))
;; SPDX-License-Identifier: LGPL-3.0-or-later
;; Keywords: lisp, scheme
;; Homepage: https://github.com/port19x/geiser-overlay
;; URL: https://github.com/port19x/geiser-overlay
;; Created: 29 Aug 2024
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; Overlay Scheme evaluation results.
;; This is mostly a s/sly-/geiser-/g of sly-overlay.
;; Sly-overlay borrows from EROS, which borrows from CIDER.
;;
;; Bind `geiser-overlay-eval-defun' to whatever you normally bind `geiser-eval-defun' to.
;;
;;; Code:

(require 'cl-lib)
(require 'geiser)
(require 'pulse)

;; Entertaining The Byte Compiler
(declare-function geiser-eval--send/wait "")
(declare-function geiser-eval--retort-result "")

;; --- Customizable settings --- ;;

(defgroup geiser-overlay nil
  "Evaluation result overlays for Common Lisp."
  :prefix "geiser-overlay-"
  :group 'lisp)

(defcustom geiser-overlay-pulse t
  "The prefix displayed in the minibuffer before a result value."
  :group 'geiser-overlay
  :type 'boolean
  :package-version '(geiser-overlay "1.1.0"))

(defcustom geiser-overlay-eval-result-prefix "=> "
  "The prefix displayed in the minibuffer before a result value."
  :group 'geiser-overlay
  :type 'string
  :package-version '(geiser-overlay "1.0.0"))

(defface geiser-overlay-result-overlay-face
  '((((class color) (background light))
     :background "grey90" :box (:line-width -1 :color "yellow"))
    (((class color) (background dark))
     :background "grey10" :box (:line-width -1 :color "black")))
  "Face used to display evaluation results at the end of line.
If `geiser-overlay-overlays-use-font-lock' is non-nil, this face is applied
with lower priority than the syntax highlighting."
  :group 'geiser-overlay
  :package-version '(geiser-overlay "1.0.0"))

(defcustom geiser-overlay-overlays-use-font-lock t
  "If non-nil, results overlays are font-locked as Clojure code.
If nil, apply `geiser-overlay-result-overlay-face' to the entire
overlay instead of font-locking it."
  :group 'geiser-overlay
  :type 'boolean
  :package-version '(geiser-overlay "1.0.0"))

(defcustom geiser-overlay-eval-result-duration 'command
  "Duration, in seconds, of eval-result overlays.

If nil, overlays last indefinitely.

If the symbol `command', they're erased before the next command."
  :group 'geiser-overlay
  :type '(choice (integer :tag "Duration in seconds")
          (const :tag "Until next command" command)
          (const :tag "Last indefinitely" nil))
  :package-version '(geiser-overlay "1.0.0"))

;; --- Overlay logic --- ;;

(defun geiser-overlay--make-overlay (l r type &rest props)
  "Place an overlay between L and R and return it.

TYPE is a symbol put on the overlay's category property.

PROPS is a plist of properties and values to add to the overlay."
  (let ((o (make-overlay l (or r l) (current-buffer))))
    (overlay-put o 'category type)
    (overlay-put o 'geiser-overlay-temporary t)
    (while props (overlay-put o (pop props) (pop props)))
    (push #'geiser-overlay--delete-overlay (overlay-get o 'modification-hooks))
    (when geiser-overlay-pulse (pulse-momentary-highlight-region l r))
    o))

(defun geiser-overlay--delete-overlay (ov &rest _)
  "Safely delete overlay OV.

Never throws errors, and can be used in an overlay's
modification-hooks."
  (ignore-errors (delete-overlay ov)))

(cl-defun geiser-overlay--make-result-overlay (value &rest props &key where duration (type 'result)
                                                  (format (concat " " geiser-overlay-eval-result-prefix "%s "))
                                                  (prepend-face 'geiser-overlay-result-overlay-face)
                                                  &allow-other-keys)
  "Place an overlay displaying VALUE at the end of line.

VALUE is used as the overlay's after-string property, meaning it
is displayed at the end of the overlay.  The overlay itself is
placed from beginning to end of current line.

Return nil if the overlay was not placed or if it might not be
visible, and return the overlay otherwise.

Return the overlay if it was placed successfully, and nil if it
failed.

This function takes some optional keyword arguments:

- If WHERE is a number or a marker, apply the overlay over the
  entire line at that place (defaulting to `point').  If it is a
  cons cell, the car and cdr determine the start and end of the
  overlay.

- DURATION takes the same possible values as the
  `geiser-overlay-eval-result-duration' variable.

- TYPE is passed to `geiser-overlay--make-overlay' (defaults to `result').

- FORMAT is a string passed to `format'.  It should have exactly
  one %s construct (for VALUE).

All arguments beyond these (PROPS) are properties to be used on
the overlay."
  (declare (indent 1))
  (while (keywordp (car props))
    (setq props (cddr props)))
  ;; If the marker points to a dead buffer, don't do anything.
  (let ((buffer (cond
                 ((markerp where) (marker-buffer where))
                 ((markerp (car-safe where)) (marker-buffer (car where)))
                 (t (current-buffer)))))
    (with-current-buffer buffer
      (save-excursion
        (when (number-or-marker-p where)
          (goto-char where))
        ;; Make sure the overlay is actually at the end of the sexp.
        (skip-chars-backward "\r\n[:blank:]")
        (let* ((beg (if (consp where)
                        (car where)
                      (save-excursion
                        (backward-sexp 1)
                        (point))))
               (end (if (consp where)
                        (cdr where)
                      (line-end-position)))
               (display-string (format format value))
               (o nil))
          (remove-overlays beg end 'category type)
          (funcall (if geiser-overlay-overlays-use-font-lock
                       #'font-lock-prepend-text-property
                     #'put-text-property)
                   0 (length display-string)
                   'face prepend-face
                   display-string)
          ;; If the display spans multiple lines or is very long, display it at
          ;; the beginning of the next line.
          (when (or (string-match "\n." display-string)
                    (> (string-width display-string)
                       (- (window-width) (current-column))))
            (setq display-string (concat " \n" display-string)))
          ;; Put the cursor property only once we're done manipulating the
          ;; string, since we want it to be at the first char.
          (put-text-property 0 1 'cursor 0 display-string)
          (when (> (string-width display-string) (* 3 (window-width)))
            (setq display-string
                  (concat (substring display-string 0 (* 3 (window-width)))
                          "...\nResult truncated.")))
          ;; Create the result overlay.
          (setq o (apply #'geiser-overlay--make-overlay
                         beg end type
                         'after-string display-string
                         props))
          (pcase duration
            ((pred numberp) (run-at-time duration nil #'geiser-overlay--delete-overlay o))
            (`command (if this-command
                          (add-hook 'pre-command-hook
                                    #'geiser-overlay--remove-result-overlay
                                    nil 'local)
                        (geiser-overlay--remove-result-overlay))))
          (let ((win (get-buffer-window buffer)))
            ;; Left edge is visible.
            (when (and win
                       (<= (window-start win) (point))
                       ;; In 24.3 `<=' is still a binary predicate.
                       (<= (point) (window-end win))
                       ;; Right edge is visible. This is a little conservative
                       ;; if the overlay contains line breaks.
                       (or (< (+ (current-column) (string-width value))
                              (window-width win))
                           (not truncate-lines)))
              o)))))))

(defun geiser-overlay--remove-result-overlay ()
  "Remove result overlay from current buffer.

This function also removes itself from `pre-command-hook'."
  (remove-hook 'pre-command-hook #'geiser-overlay--remove-result-overlay 'local)
  (remove-overlays nil nil 'category 'result))

(defun geiser-overlay--eval-overlay (value point)
  "Make overlay for VALUE at POINT."
  (geiser-overlay--make-result-overlay (format "%s" value)
    :where point
    :duration geiser-overlay-eval-result-duration)
  value)

;; yoinked from sly directly
(defun geiser-overlay-region-for-defun-at-point (&optional pos)
  "Return a list (START END) for the positions of defun at POS.
POS defaults to point"
  (save-excursion
    (save-match-data
      (goto-char (or pos (point)))
      (end-of-defun)
      (let ((end (point)))
        (beginning-of-defun)
        (list (point) end)))))

(defun geiser-overlay--defun-at-point ()
  "Get the sexp at point as a string."
  (pcase (geiser-overlay-region-for-defun-at-point)
    (`(,start ,end) (string-trim (buffer-substring-no-properties start end)))))

(defun geiser-overlay--enquote ()
  "Prepare the scheme expression string for evaluation by geiser."
  `(:eval (:scm ,(geiser-overlay--defun-at-point))))

;; --- API --- ;;

;;;###autoload
(defun geiser-overlay-eval-defun ()
  "Evaluate the form at point and overlay the results."
  (interactive)
  (let ((result (geiser-eval--retort-result (geiser-eval--send/wait (geiser-overlay--enquote)))))
    (geiser-overlay--eval-overlay
     result
     (save-excursion
       (end-of-defun)
       (point)))
    (message "%s" result)))

(provide 'geiser-overlay)
;;; geiser-overlay.el ends here

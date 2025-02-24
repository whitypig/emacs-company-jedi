;;; company-jedi.el --- company-mode completion back-end for Python JEDI -*- lexical-binding: t; -*-

;; Copyright (C) 2015 by Syohei YOSHIDA

;; Author: Boy <boyw165@gmail.com>
;; Package-Requires: ((emacs "24") (cl-lib "0.5") (company "0.8.11") (jedi-core "0.2.7"))
;; Version: 0.04

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;;  This is a company-backend for emacs-jedi. Add this backend to the
;;  `company-backends' and enjoy the power.
;;  e.g.
;;  ;; Basic usage.
;;  (add-to-list 'company-backends 'company-jedi)
;;  ;; Advanced usage.
;;  (add-to-list 'company-backends '(company-jedi company-files))
;;
;;  Check https://github.com/company-mode/company-mode for details.
;;
;;; Code:

;; GNU Library.
(eval-when-compile (require 'cl-lib))
(require 'company)
(require 'jedi-core)

(defgroup company-jedi nil
  "Completion back-end for Python JEDI."
  :group 'company)

(defun company-jedi-prefix ()
  "Get a prefix from current position."
  (company-grab-symbol-cons "\\." 2))

(defun company-jedi-collect-candidates (completion)
  "Return a candidate from a COMPLETION reply."
  (let ((candidate (plist-get completion :word)))
    (when candidate
      (put-text-property 0 1 :doc (plist-get completion :doc) candidate)
      (put-text-property 0 1 :symbol (plist-get completion :symbol) candidate)
      (put-text-property 0 1 :description (plist-get completion :description) candidate)
      candidate)))

(defun company-jedi-candidates (callback)
  "Return company candidates with CALLBACK."
  (deferred:nextc
    (jedi:call-deferred 'complete)
    (lambda (reply)
      (let ((candidates (mapcar 'company-jedi-collect-candidates reply)))
        (funcall callback candidates)))))

(defun company-jedi-meta (candidate)
  "Return company meta string for a CANDIDATE."
  (get-text-property 0 :description candidate))

(defun company-jedi-annotation (candidate)
  "Return company annotation string for a CANDIDATE."
  (format "[%s]" (get-text-property 0 :symbol candidate)))

(defun company-jedi-doc-buffer (candidate)
  "Return a company documentation buffer from a CANDIDATE."
  (company-doc-buffer (get-text-property 0 :doc candidate)))

;;;###autoload
(defun company-jedi (command &optional arg &rest ignored)
  "`company-mode' completion back-end for `jedi-code.el'.
Provide completion info according to COMMAND and ARG.  IGNORED, not used."
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-jedi))
    (prefix (and (derived-mode-p 'python-mode)
                 (not (company-in-string-or-comment))
                 (or (company-jedi-prefix) 'stop)))
    (candidates (cons :async 'company-jedi-candidates))
    (meta (company-jedi-meta arg))
    (annotation (company-jedi-annotation arg))
    (doc-buffer (company-jedi-doc-buffer arg))
    (location nil)
    (sorted t)))

(defun company-jedi--expand-snippet (candidate)
  (when (fboundp 'yas-expand-snippet)
    (let ((symbol (get-text-property 0 :symbol candidate))
          (doc (get-text-property 0 :doc candidate))
          (snippet nil))
      ;; (message "DEBUG: symbol=%s" symbol)
      ;; (message "DEBUG: doc=%s" doc)
      (cond
       ((member symbol '("f" "c"))
        ;; DEBUG: doc=bisect_right(a, x, lo=0, hi=None)...
        ;; This can be a function.
        ;; doc may have multiple lines and the first line is what we need.
        (setq snippet
              (company-jedi--make-snippet-template candidate
                                                   (car (split-string doc "[\n]"))))
        ;; (message "DEBUG: snippet=|%s|" snippet)
        (and snippet (yas-expand-snippet snippet)))
       (t
        ;; Do nothing for now.
        nil)))))

(defun company-jedi--make-snippet-template (candidate doc)
  ;; (message "DEBUG: doc=%s" doc)
  (let* ((params
          (and (string-match-p (format "%s([^)]*)" candidate) doc)
               (split-string (substring-no-properties doc
                                                      (1+ (string-match-p "(" doc))
                                                      (string-match-p ")" doc))
                             "[ ,]"
                             t)))
         (ix 1))
    (concat "${1:("
            (cl-reduce
             (lambda (x y)
               (concat
                x
                (cond
                 ((string-match-p "=" y)
                  ;; default argument
                  (concat (if (= 1 ix)
                              ""
                            (format "${%d:, }" (incf ix)))
                          (format "${%d:%s}" (incf ix) y)))
                 (t
                  (format "%s${%d:%s}"
                          (if (= 1 ix) "" ", ")
                          (incf ix)
                          y)))))
             params
             :initial-value "")
            ")}$0")))

(defun company-jedi--set-backend ()
  ;; For debugging purpose
  (interactive)
  (setq company-backends '(company-jedi-with-yasnippet)))

(defun company-jedi-with-yasnippet (command &optional arg &rest ignored)
  "`company-mode' completion back-end for `jedi-code.el'.
Provide completion info according to COMMAND and ARG.  IGNORED, not used.

When yasnippet is available, try to create and expand a snippet for a
function candidate on completion.  If you need only a function name,
just perform \"C-d\". This will delete all the parameters including
parentheses. Snippets for default arguments are expanded by default,
but you can erase them as well as separators, which are \", \", by
\"C-d\", too."
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-jedi-with-yasnippet))
    (prefix (and (derived-mode-p 'python-mode)
                 (not (company-in-string-or-comment))
                 (or (company-jedi-prefix) 'stop)))
    (candidates (cons :async 'company-jedi-candidates))
    (meta (company-jedi-meta arg))
    (annotation (company-jedi-annotation arg))
    (doc-buffer (company-jedi-doc-buffer arg))
    (location nil)
    (sorted t)
    (post-completion (company-jedi--expand-snippet arg))))

(provide 'company-jedi)

;;; company-jedi.el ends here

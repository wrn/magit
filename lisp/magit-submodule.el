;;; magit-submodule.el --- submodule support for Magit  -*- lexical-binding: t -*-

;; Copyright (C) 2011-2015  The Magit Project Contributors
;;
;; You should have received a copy of the AUTHORS.md file which
;; lists all contributors.  If not, see http://magit.vc/authors.

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Magit is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit.  If not, see http://www.gnu.org/licenses.

;;; Code:

(require 'magit)

;;; Commands

;;;###autoload (autoload 'magit-submodule-popup "magit-submodule" nil t)
(magit-define-popup magit-submodule-popup
  "Popup console for submodule commands."
  'magit-commands nil nil
  :man-page "git-submodule"
  :actions  '((?a "Add"    magit-submodule-add)
              (?b "Setup"  magit-submodule-setup)
              (?u "Update" magit-submodule-update)
              (?f "Fetch"  magit-submodule-fetch)
              (?d "Deinit" magit-submodule-deinit)
              (?C "Configure..." magit-submodule-config-popup)))

;; TODO(?): add functions to set/see individual variables
(defun magit-submodule-edit-gitsubmodules ()
  (find-file ".gitmodules"))
(defun magit-submodule-edit-config ()
  (find-file ".git/config"))

(magit-define-popup magit-submodule-config-popup
  "Configure submodule related git variables."
  'magit-commands nil nil
  :man-page "git-submodule"
  :actions '((?e "Edit .gitmodules" magit-submodule-edit-gitsubmodules)
             (?E "Edit .git/config" magit-submodule-edit-config)
             (?i "Copy missing settings from .gitmodules to .git/config"
                 magit-subdmodule-init)
             (?s "Update url from .gitmodules to .git/config"
                 magit-submodule-sync)))

;;;###autoload
(defun magit-submodule-add (url &optional path name)
  "Add the repository at URL as a submodule.

Optional PATH is the path to the submodule relative to the root
of the superproject.  If it is nil, then the path is determined
based on the URL.

Optional NAME is the name of the submodule.  If it is nil, then
PATH also becomes the name."
  (interactive
   (magit-with-toplevel
     (let* ((url (magit-read-string-ns
                  "Add submodule (remote url)"
                  (magit-get "remote" (or (magit-get-remote) "origin") "url")))
            (path (read-directory-name
                   "Submodule path: "
                   nil nil nil (and (string-match "\\([^./]+\\)\\(\\.git\\)?$" url)
                                    (match-string 1 url)))))
       (list url
             (directory-file-name path)
             (magit-read-string-ns
              "Submodule name" nil nil
              (or (--keep (-let [(var val) (split-string it "=")]
                            (and (equal val path)
                                 (cadr (split-string var "\\."))))
                          (magit-git-lines "config" "--list" "-f" ".gitmodules"))
                  (file-name-nondirectory (directory-file-name path))))))))
  (magit-run-git "submodule" "add" (and name (list "--name" name)) url path))

;;;###autoload
(defun magit-submodule-setup ()
  "Clone and register missing submodules and checkout appropriate commits."
  (interactive)
  (magit-submodule-update t))

;;;###autoload
(defun magit-submodule-init ()
  "Register submodules listed in \".gitmodules\" into \".git/config\"."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "init")))

;;;###autoload
(defun magit-submodule-update (&optional init)
  "Clone missing submodules and checkout appropriate commits.
With a prefix argument also register submodules in \".git/config\"."
  (interactive "P")
  (magit-with-toplevel
    (magit-run-git-async "submodule" "update" (and init "--init"))))

;;;###autoload
(defun magit-submodule-sync ()
  "Update each submodule's remote URL according to \".gitmodules\"."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "sync")))

;;;###autoload
(defun magit-submodule-fetch (&optional all)
  "Fetch all submodules.
With a prefix argument fetch all remotes."
  (interactive "P")
  (magit-with-toplevel
    (magit-run-git-async "submodule" "foreach"
                         (format "git fetch %s || true" (if all "--all" "")))))

;;;###autoload
(defun magit-submodule-deinit (path)
  "Unregister the submodule at PATH."
  (interactive
   (list (magit-completing-read "Deinit module" (magit-get-submodules)
                                nil t nil nil (magit-section-when module))))
  (magit-with-toplevel
    (magit-run-git-async "submodule" "deinit" path)))

;;; Sections

;;;###autoload
(defun magit-insert-submodules ()
  "Insert sections for all modules.
For each section insert the path and the output of `git describe --tags'."
  (-when-let (modules (magit-get-submodules))
    (magit-insert-section (modules nil t)
      (magit-insert-heading "Modules:")
      (magit-with-toplevel
        (dolist (module modules)
          (let ((default-directory
                  (expand-file-name (file-name-as-directory module))))
            (magit-insert-section (module module t)
              (insert (format "%-25s " module))
              (if (not (file-exists-p ".git")) (insert " (unitialized)")
                (insert (format "%-25s "
                                (--if-let (magit-get-current-branch)
                                    (propertize it 'face 'magit-branch-local)
                                  (propertize "(detached)" 'face 'warning))))
                (--when-let (magit-git-string "describe" "--tags")
                  (when (string-match-p "\\`[0-9]" it)
                    (insert ?\s))
                  (insert it)))
              (insert ?\n)))))
      (insert ?\n))))

;;;###autoload
(defun magit-insert-modules-unpulled-from-upstream ()
  "Insert sections for modules that haven't been pulled from the upstream.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unpulled from @{upstream}"
                              'modules-unpulled-from-upstream
                              'magit-get-upstream-ref
                              "HEAD..%s"))

;;;###autoload
(defun magit-insert-modules-unpulled-from-pushremote ()
  "Insert sections for modules that haven't been pulled from the push-remote.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unpulled from <push-remote>"
                              'modules-unpulled-from-pushremote
                              'magit-get-push-branch
                              "HEAD..%s"))

;;;###autoload
(defun magit-insert-modules-unpushed-to-upstream ()
  "Insert sections for modules that haven't been pushed to the upstream.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unmerged into @{upstream}"
                              'modules-unpushed-to-upstream
                              'magit-get-upstream-ref
                              "%s..HEAD"))

;;;###autoload
(defun magit-insert-modules-unpushed-to-pushremote ()
  "Insert sections for modules that haven't been pushed to the push-remote.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unpushed to <push-remote>"
                              'modules-unpushed-to-pushremote
                              'magit-get-push-branch
                              "%s..HEAD"))

(defun magit-submodule-visit (module &optional other-window)
  "Visit MODULE by calling `magit-status' on it.
Offer to initialize MODULE if it's not checked out yet."
  (interactive (list (or (magit-section-when module)
                         (user-error "No submodule at point"))
                     current-prefix-arg))
  (let ((path (expand-file-name module)))
    (if (or (file-exists-p (expand-file-name ".git" module))
            (not (y-or-n-p (format "Setup submodule '%s' first?"
                                   module))))
        (magit-diff-visit-directory path other-window)
      (magit-submodule-setup module)
      (set-process-sentinel
       (lambda (process event)
         (when (memq (process-status process) '(exit signal))
           (let ((magit-process-raise-error t))
             (magit-process-sentinel process event)))
         (when (and (eq (process-status process) 'exit)
                    (= (process-exit-status process) 0))
           (magit-diff-visit-directory path other-window)))))))

(defvar magit-module-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [C-return] 'magit-submodule-visit)
    (define-key map "\C-j"     'magit-submodule-visit)
    (define-key map [remap magit-visit-thing]  'magit-submodule-visit)
    (define-key map [remap magit-delete-thing] 'magit-submodule-deinit)
    (define-key map "K" 'magit-file-untrack)
    (define-key map "R" 'magit-file-rename)
    map)
  "Keymap for `module' sections.")

(defun magit--insert-modules-logs (heading type fn format)
  "For internal use, don't add to a hook."
  (-when-let (modules (magit-get-submodules))
    (magit-insert-section section ((eval type) nil t)
      (string-match "\\`\\(.+\\) \\([^ ]+\\)\\'" heading)
      (magit-insert-heading
        (concat
         (propertize (match-string 1 heading) 'face 'magit-section-heading) " "
         (propertize (match-string 2 heading) 'face 'magit-branch-remote) ":"))
      (magit-with-toplevel
        (dolist (module modules)
          (let ((default-directory
                  (expand-file-name (file-name-as-directory module))))
            (--when-let (and (magit-file-accessible-directory-p default-directory)
                             (funcall fn))
              (magit-insert-section sec (file module t)
                (magit-insert-heading
                  (concat (propertize module 'face 'magit-diff-file-heading) ":"))
                (magit-git-wash (apply-partially 'magit-log-wash-log 'module)
                  "log" "--oneline" (format format it))
                (when (> (point) (magit-section-content sec))
                  (delete-char -1)))))))
      (if (> (point) (magit-section-content section))
          (insert ?\n)
        (magit-cancel-section)))))

;;; magit-submodule.el ends soon

(define-obsolete-function-alias 'magit-insert-unpulled-module-commits
  'magit-insert-modules-unpulled-from-upstream "Magit 2.6.0")
(define-obsolete-function-alias 'magit-insert-unpushed-module-commits
  'magit-insert-modules-unpushed-to-upstream "Magit 2.6.0")

(provide 'magit-submodule)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; magit-submodule.el ends here

;;; init.el --- Emacs setup for Python REPL-driven development -*- lexical-binding: t; -*-

;; Package system setup.
(require 'package)
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

;; Only refresh archives if we do not already have them.
(unless package-archive-contents
  (package-refresh-contents))

;; Bootstrap use-package.
(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(eval-when-compile
  (require 'use-package))
(require 'bind-key)
(setq use-package-always-ensure t)

;; Keep customizations in a separate file.
(setq custom-file (locate-user-emacs-file "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file nil 'nomessage))

;; Sensible defaults.
(setq inhibit-startup-screen t)
(fset 'yes-or-no-p 'y-or-n-p)

;; Dark theme that pops, including for terminal Emacs.
(setq frame-background-mode 'dark)
(setq-default cursor-type 'bar)

;; Keep a bit of padding without removing window controls.
(add-to-list 'default-frame-alist '(internal-border-width . 8))

;; GTK menu/tool/scroll bars stay light under many system themes, so disable them.
(when (fboundp 'menu-bar-mode)
  (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))

(defun b/load-dark-theme (&optional _frame)
  "Load a high-contrast dark theme."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'modus-vivendi-tinted t))
(add-hook 'after-make-frame-functions #'b/load-dark-theme)
(b/load-dark-theme)

;; Window navigation with M-j/i/l/k.
(require 'windmove)
(global-set-key (kbd "M-j") #'windmove-left)
(global-set-key (kbd "M-i") #'windmove-up)
(global-set-key (kbd "M-l") #'windmove-right)
(global-set-key (kbd "M-k") #'windmove-down)
(global-set-key (kbd "<f11>") #'toggle-frame-fullscreen)
(global-set-key (kbd "M-<return>") #'toggle-frame-fullscreen)

;; Global font scaling shortcuts (apply to all buffers).
(defvar b/default-face-height nil
  "Default face height captured at startup.")
(defvar b/global-font-scale-step 10
  "Step size for global font scaling.")

(defun b/clear-text-scale-in-all-buffers ()
  "Reset any buffer-local `text-scale-mode' adjustments."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (bound-and-true-p text-scale-mode)
        (text-scale-set 0)))))

(defun b/global-font-scale-adjust (delta)
  "Adjust the default face height by DELTA across all buffers."
  (unless b/default-face-height
    (setq b/default-face-height (face-attribute 'default :height nil 'default)))
  (b/clear-text-scale-in-all-buffers)
  (let* ((current (face-attribute 'default :height nil 'default))
         (new-height (max 50 (+ current delta))))
    (set-face-attribute 'default nil :height new-height)
    (message "Global font height: %s" new-height)))

(defun b/global-font-scale-increase ()
  "Increase font size across all buffers."
  (interactive)
  (b/global-font-scale-adjust b/global-font-scale-step))

(defun b/global-font-scale-decrease ()
  "Decrease font size across all buffers."
  (interactive)
  (b/global-font-scale-adjust (- b/global-font-scale-step)))

(defun b/global-font-scale-reset ()
  "Reset global font size to the startup default."
  (interactive)
  (unless b/default-face-height
    (setq b/default-face-height (face-attribute 'default :height nil 'default)))
  (b/clear-text-scale-in-all-buffers)
  (set-face-attribute 'default nil :height b/default-face-height)
  (message "Global font height reset: %s" b/default-face-height))

;; Bind common variants for Ctrl-Shift-+ / Ctrl-Shift--.
(global-set-key (kbd "C-+") #'b/global-font-scale-increase)
(global-set-key (kbd "C-=") #'b/global-font-scale-increase)
(global-set-key (kbd "C-S-+") #'b/global-font-scale-increase)
(global-set-key (kbd "C--") #'b/global-font-scale-decrease)
(global-set-key (kbd "C-_") #'b/global-font-scale-decrease)
(global-set-key (kbd "C-S--") #'b/global-font-scale-decrease)
(global-set-key (kbd "C-0") #'b/global-font-scale-reset)

;; Python REPL-driven development.
(use-package python
  :mode ("\\.py\\'" . python-mode)
  :init
  (setq python-indent-guess-indent-offset-verbose nil)

  (defun b/python-shell-interpreter ()
    "Use the Miniforge Python, falling back to python3."
    (let ((miniforge-python "/home/b/miniforge3/bin/python"))
      (if (file-executable-p miniforge-python)
          miniforge-python
        "python3")))

  (defun b/python-shell-interpreter-args ()
    "Return interpreter args suitable for interactive REPL work."
    (if (string-match-p "ipython" (b/python-shell-interpreter))
        "-i --simple-prompt"
      "-i"))

  (defun b/python-shell-wait-for-ready (process &optional timeout)
    "Wait until PROCESS has produced its first prompt."
    (let ((timeout (or timeout 5.0))
          (elapsed 0.0)
          (step 0.1))
      (while (and (< elapsed timeout)
                  (process-live-p process)
                  (with-current-buffer (process-buffer process)
                    (not python-shell--first-prompt-received)))
        (accept-process-output process step)
        (setq elapsed (+ elapsed step)))))

  (defun b/python-shell-ensure-running ()
    "Start a Python REPL if one is not already running."
    (let ((process (python-shell-get-process)))
      (unless process
        (run-python (python-shell-calculate-command) nil nil)
        (setq process (python-shell-get-process)))
      (when (and process
                 (with-current-buffer (process-buffer process)
                   (not python-shell--first-prompt-received)))
        (b/python-shell-wait-for-ready process))
      process))

  (defun b/python-shell-arrange-windows (&optional process)
    "Ensure a 50/50 split with the REPL on the right."
    (let* ((process (or process (python-shell-get-process)))
           (repl-buffer (and process (process-buffer process)))
           (source-window (selected-window)))
      (when (and process repl-buffer)
        (let ((repl-window (get-buffer-window repl-buffer t)))
          (unless (and (= (length (window-list)) 2)
                       repl-window
                       (eq (window-buffer (next-window source-window)) repl-buffer))
            (delete-other-windows source-window)
            (setq repl-window (split-window-right))
            (set-window-buffer repl-window repl-buffer)
            (balance-windows)))
        (select-window source-window))))

  (defun b/python-shell-switch-to-repl ()
    "Jump to the active Python REPL, starting one if needed."
    (interactive)
    (let ((process (b/python-shell-ensure-running)))
      (b/python-shell-arrange-windows process)
      (select-window (get-buffer-window (process-buffer process) t))))

  (defun b/python-shell-send-region-or-statement ()
    "Send the active region, or the current statement, to the REPL."
    (interactive)
    (let ((process (b/python-shell-ensure-running)))
      (b/python-shell-arrange-windows process))
    (if (use-region-p)
        (python-shell-send-region (region-beginning) (region-end))
      (python-shell-send-statement)))

  (defun b/python-shell-send-region (start end)
    "Send region to the REPL, starting it if necessary."
    (interactive "r")
    (let ((process (b/python-shell-ensure-running)))
      (b/python-shell-arrange-windows process))
    (python-shell-send-region start end))

  (defun b/python-shell-send-buffer ()
    "Send buffer to the REPL, starting it if necessary."
    (interactive)
    (let ((process (b/python-shell-ensure-running)))
      (b/python-shell-arrange-windows process))
    (python-shell-send-buffer))

  (defun b/python-shell-send-defun ()
    "Send defun to the REPL, starting it if necessary."
    (interactive)
    (let ((process (b/python-shell-ensure-running)))
      (b/python-shell-arrange-windows process))
    (python-shell-send-defun))

  (defun b/python-mode-setup ()
    "Configure Python mode for REPL-driven development."
    (setq-local python-shell-interpreter (b/python-shell-interpreter))
    (setq-local python-shell-interpreter-args (b/python-shell-interpreter-args))
    (local-set-key (kbd "C-c C-z") #'b/python-shell-switch-to-repl)
    (local-set-key (kbd "C-c C-|") #'b/python-shell-send-region-or-statement)
    (local-set-key (kbd "C-c C-r") #'b/python-shell-send-region)
    (local-set-key (kbd "C-c C-c") #'b/python-shell-send-buffer)
    (local-set-key (kbd "C-c C-f") #'b/python-shell-send-defun)
    (local-set-key (kbd "C-c C-s") #'run-python))
  :config
  ;; Python 3.13+ defaults to pyrepl, which warns under TERM=dumb (comint).
  (add-to-list 'python-shell-process-environment "PYTHON_BASIC_REPL=1")
  :hook (python-mode . b/python-mode-setup))

;;; init.el ends here

;;; VBAPL office LISP - loader for AutoCAD and BricsCAD.
;;;
;;; Add THIS file, and only this one, to the Startup Suite:
;;;   APPLOAD > Startup Suite: Contents... > Add... > <build folder>\vbapl.lsp
;;; and put the build folder on the support file search path, so that
;;; (findfile "vbapl-lisp.exe") finds the helper that sits beside this file.
;;;
;;; At every drawing it asks vbapl-lisp.exe for the office routines and
;;; evaluates them straight into this session, one top-level form per line.
;;; The routines never exist on disk as a readable file. The helper answers
;;; only when AutoCAD or BricsCAD started it, when Start.bat unlocked this PC
;;; (the 7 days / 100 starts licence), and while Start.bat is still running.
;;;
;;; Needs full AutoCAD or BricsCAD: AutoCAD LT has no ActiveX (vlax-*).

(vl-load-com)

;; A COM result as a plain value.
(defun vbapl:val (v)
  (if (= (type v) 'variant) (vlax-variant-value v) v)
)

;; A COM boolean - :vlax-true, T, or a non-zero number depending on the CAD.
(defun vbapl:true-p (v)
  (setq v (vbapl:val v))
  (or (= v :vlax-true) (= v T) (and (numberp v) (/= v 0)))
)

;; Whether line starts with tag.
(defun vbapl:tag-p (line tag)
  (= (substr line 1 (strlen tag)) tag)
)

;; Put dir on the support path, so dialogs (.dcl) are found, and drop the
;; session folders earlier loads added - the support path is saved with the
;; user's profile, so they would pile up.
(defun vbapl:support-dir (dir / files old keep part i)
  (setq files (vla-get-files (vla-get-preferences (vlax-get-acad-object)))
        old   (strcat (vla-get-supportpath files) ";")
        keep  "")
  (while (setq i (vl-string-search ";" old))
    (setq part (substr old 1 i)
          old  (substr old (+ i 2)))
    (if (and (/= part "")
             (not (vl-string-search "\\VBAPL\\LISP\\SESSION\\" (strcase part))))
      (setq keep (strcat keep part ";"))
    )
  )
  (vla-put-supportpath files (strcat keep dir))
)

(defun vbapl:load (/ exe shell job out line done failed release locked)
  (setq done 0 failed 0)
  (cond
    ((not (setq exe (findfile "vbapl-lisp.exe")))
     (princ "\nVBAPL: vbapl-lisp.exe not found - add the build folder to the support file search path.")
    )
    ((vl-catch-all-error-p
       (setq job (vl-catch-all-apply
                   '(lambda ()
                      (setq shell (vlax-create-object "WScript.Shell"))
                      (vlax-invoke-method shell 'Exec (strcat "\"" exe "\" forms")))
                   nil)))
     (princ (strcat "\nVBAPL: could not start vbapl-lisp.exe - " (vl-catch-all-error-message job)))
    )
    (T
     (setq out (vbapl:val (vlax-get-property job 'StdOut)))
     (while (not (vbapl:true-p (vlax-get-property out 'AtEndOfStream)))
       (setq line (vbapl:val (vlax-invoke-method out 'ReadLine)))
       (cond
         ((vbapl:tag-p line "FORM ")
          (if (vl-catch-all-error-p
                (vl-catch-all-apply '(lambda (s) (eval (read s))) (list (substr line 6))))
            (setq failed (1+ failed))
            (setq done (1+ done))
          )
         )
         ((vbapl:tag-p line "DIR ") (vbapl:support-dir (substr line 5)))
         ((vbapl:tag-p line "DES ") (vl-catch-all-apply 'load (list (substr line 5))))
         ((vbapl:tag-p line "DLL ")
          (if (vl-catch-all-error-p
                (vl-catch-all-apply '(lambda (p) (vl-cmdf "_.NETLOAD" p)) (list (substr line 5))))
            (setq failed (1+ failed))
            (setq done (1+ done))
          )
         )
         ((vbapl:tag-p line "OK ") (setq release (substr line 4)))
         ((vbapl:tag-p line "LOCKED ") (setq locked (substr line 8)))
       )
     )
     (if shell (vlax-release-object shell))
     (cond
       (locked (princ (strcat "\nVBAPL: office LISP not loaded - " locked)))
       (release
        (princ (strcat "\nVBAPL: office LISP loaded (release " release ")"
                       (if (> failed 0) (strcat " - " (itoa failed) " part(s) failed to load") "")
                       "."))
       )
     )
    )
  )
  (princ)
)

(vbapl:load)
(princ)

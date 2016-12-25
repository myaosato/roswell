(ros:include '("util-install-quicklisp"))
(ros:quicklisp :environment nil)
(unless (find-package :plump)
  (ql:quickload '(:plump) :silent t))

(defpackage :roswell.install.slime
  (:use :cl :roswell.install :roswell.locations :roswell.util))
(in-package :roswell.install.slime)

(defun slime-help (argv)
  (let ((s *error-output*))
    (format s "[WIP]Usage: ~A slime install/use/list/delete version ~%" (opt "wargv0")))
  (cons t argv))

(defun slime-get-version ()
  (format *error-output* "Checking version to install....~%")
  (github-version (slime-git-version-uri) "slime" (lambda (href) (subseq href (+ 2 (position #\/ href :from-end t))))))

(defun name-error (name)
  (format *error-output* "~A is not appropriate format. ~% quicklisp dist for XXXX.XX.XX , slime version for X.XX.~%" name)
  (ros:quit 1))

(defun slime-from-git (name)
  (let* ((str (slime-uri))
         (end (position #\/ str :from-end t))
         (end2 (position #\. str :from-end t))
         (start (position #\/ str :from-end t :end end)))
    (clone-github
     (subseq str (1+ start) end)
     (subseq str (1+ end) end2)
     :path "lisp/slime" :branch (format nil "v~A" name) :alias name))
  :git)

(defun slime-from-ql (name)
  (let ((dist-file (merge-pathnames "tmp/slime-distinfo.txt" (homedir)))
        (versions-uri (ql-util:make-versions-url ql:*initial-dist-url*))
        (versions-file (merge-pathnames "tmp/slime-versions.txt" (homedir)))
        (release-file (merge-pathnames "tmp/slime-release.txt" (homedir)))
        (archive-file (merge-pathnames "tmp/slime.tgz" (homedir)))
        (extract-path (merge-pathnames "lisp/slime/tmp/" (homedir)))
        dist)
    (unless (ql-impl-util:probe-directory extract-path)
      (download versions-uri versions-file)
      (let* ((key (substitute #\- #\. name))
             (uri (with-open-file (in versions-file)
                    (loop
                      for e = (ql-util:split-spaces (read-line in nil nil))
                      while e
                      when (equal key (first e))
                        return (second e)))))
        (if uri
            (download uri dist-file)
            (progn
              (format *error-output* "invalid version ~A" name)
              (ros:quit 1))))
      (setq dist (ql-dist::make-dist-from-file dist-file))
      (download (ql-dist::release-index-url dist)
                release-file)
      (with-open-file (in release-file)
        (loop for line = (read-line in nil nil)
              while line
              for list = (ql-util:split-spaces line)
              when (equal (first list) "slime")
                do (download (second list) archive-file)))
      (uiop/filesystem:delete-directory-tree (ensure-directories-exist extract-path) :validate t)
      (expand archive-file (ensure-directories-exist extract-path))
      (prog1
          (ql-impl-util:rename-directory
           (first (directory (make-pathname :defaults extract-path :name :wild :type :wild)))
           (merge-pathnames (format nil "lisp/slime/~A/" name) (homedir)))
        (uiop/filesystem:delete-directory-tree (ensure-directories-exist extract-path) :validate t))))
  :ql)

(defun slime-write-helper ()
  (let* ((target (merge-pathnames "helper.el" (homedir)))
         (enough (enough-namestring target (user-homedir-pathname))))
    (unless (equal (pathname enough) target)
      (setf enough (format nil "~~/~A" enough)))
    (uiop:copy-file
     (make-pathname
      :defaults #.*load-pathname*
      :name "helper" :type "el")
     target)
    (format *error-output* "~{~A~%~}"
            `(,(format nil "helper.el installed in ~S" (namestring target)) ""
              "To use, add this to your ~/.emacs:" ""
              ,(format nil "  (load (expand-file-name ~S))" enough)))))

(defun slime-install (argv)
  (let ((name (or (getf argv :version) (substitute #\. #\- (ql:dist-version "quicklisp")))))
    (unless (loop for x across name
                  always (or (digit-char-p x)
                             (eql x #\.)))
      (name-error name))
    (case (count #\. name)
      (1 (slime-from-git name))
      (2 (or
          (ignore-errors (slime-from-git name)) ;; 2.10.1 couldn't be install without this line.
          (slime-from-ql name)))
      (t (name-error name)))
    (setf (config "slime.version") name)
    (slime-write-helper))
  (cons t argv))

(defun slime (type)
  (case type
    (:help '(slime-help))
    (:install `(slime-install))
    (:list 'slime-get-version)))
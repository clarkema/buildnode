(in-package :common-lisp-user)

(defpackage :net.acceleration.buildnode.excel
    (:nicknames :excel-xml :buildnode-excel :excel)
  (:use :common-lisp :buildnode :iterate :arnesi)
  (:export
   #:with-excel-workbook
   #:with-excel-workbook-string
   #:with-excel-workbook-file
   #:default-excel-styles
   #:?mso-application
   #:def-excel-tag
   #:set-index
   #:link-to
   #:build-excel-cell-reference
   #:set-merge
   ))
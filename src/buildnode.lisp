(in-package :net.acceleration.buildnode)
(cl-interpol:enable-interpol-syntax)

;;;;  Common string util, stoplen from adwutils
(defparameter +common-white-space-trimbag+
  '(#\space #\newline #\return #\tab
    #\u00A0 ;; this is #\no-break_space
    ))

(defun trim-whitespace (s)
  (string-trim +common-white-space-trimbag+ s))

(defun trim-and-nullify (s)
  "trims the whitespace from a string returning nil
   if trimming produces an empty string or the string 'nil' "
  (when s
    (let ((s (trim-whitespace s)))
      (cond ((zerop (length s)) nil)
	    ((string-equal s "nil") nil)
	    (T s)))))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar *document* ()
  "A variable that holds the current document that is being built. see
  with-document.")

(defmacro eval-always (&body body)
  `(eval-when (:compile-toplevel :load-toplevel :execute),@body))

(defun flatten-children (kids &optional (doc *document*))
  "Handles flattening nested lists and vectors of nodes
   into a single flat list of children
  "
  (iter (for kid in (alexandria:ensure-list kids))
	(typecase kid
	  (string (collecting (if doc
				  (dom:create-text-node doc kid)
				  kid)))
	  ((or dom:element dom:node) (collecting kid))
	  (list (nconcing (flatten-children kid doc)))
	  (vector (nconcing
		   (flatten-children
		    (iter (for sub-kid in-sequence kid) (collect sub-kid))
		    doc)))
	  (T (collecting (let ((it (princ-to-string kid)))
			   (if doc
			       (dom:create-text-node doc it)
			       it)))))))

(defun %merge-conts (&rest conts)
  "Takes many continuations and makes a single continuation that
   iterates through each of the arguments in turn"
  (setf conts (remove-if #'null conts))
  (when conts
    (lambda ()
      (let ((rest (rest conts)))
	(multiple-value-bind (item new-cont) (funcall (first conts))
	  (when new-cont (push new-cont rest))
	  (values item (when rest
			 (apply #'%merge-conts rest))))))))

(defun %walk-dom-cont (tree)
  "calls this on a dom tree (or tree list) and you get back
   a node and a continuation function.

   repeated calls to the continuation each return the next node
   and the next walker continuation
  "
  (typecase tree
    (null nil)
    ((or vector list)
       (when (plusp (length tree))
	 (multiple-value-bind (item cont) (%walk-dom-cont (elt tree 0) )
	   (values
	     item (%merge-conts
		   cont (lambda () (%walk-dom-cont (subseq tree 1))))))))
    (dom:document (%walk-dom-cont (dom:child-nodes tree)))
    (dom:text tree)
    (dom:element
       (values
	 tree
	 (when (> (length (dom:child-nodes tree)) 0)
	   (lambda () (%walk-dom-cont (dom:child-nodes tree) )))))))

(defun depth-first-nodes (tree)
  "get a list of the nodes in a depth first traversal of the dom trees"
  (iter
    (with cont = (lambda () (%walk-dom-cont tree)))
    (if cont
	(multiple-value-bind (item new-cont) (funcall cont)
	  (when item (collect item))
	  (setf cont new-cont))
	(terminate))))

(iterate:defmacro-driver (FOR node in-dom tree)
  "A driver that will walk over every node in a set of dom trees"
  (let ((kwd (if generate 'generate 'for))
	(cont (gensym "CONT-"))
	(new-cont (gensym "NEW-CONT-"))
	(genned-node (gensym "GENNED-NODE-")))    
    `(progn
       (with ,cont = (lambda () (%walk-dom-cont ,tree)))
       (,kwd ,node next
	     (if (null ,cont)
		 (terminate)
		 (multiple-value-bind (,genned-node ,new-cont) (funcall ,cont)
		   (setf ,cont ,new-cont)
		   ,genned-node)))
       (unless ,node (next-iteration)))))

(iterate:defmacro-driver (FOR parent in-dom-parents node)
  "A driver that will return each parent node up from a starting node
   until we get to a null parent"
  (let ((kwd (if generate 'generate 'for)))
    `(progn
       ;; (with ,cont = (lambda () (%walk-dom-cont ,tree)))
       (,kwd ,parent next
	     (if (first-iteration-p)
		 (dom:parent-node ,node)
		 (if (null ,parent)
		     (terminate)
		     (dom:parent-node ,parent))))
       (unless ,parent (next-iteration)))))

(iterate:defmacro-driver (FOR kid in-dom-children nodes)
  "iterates over the children of a dom node as per flatten-children"
  (let ((kwd (if generate 'generate 'for))
	(nl (gensym "NL-")))
    `(progn
       (with ,nl =
	     (flatten-children
	      (typecase ,nodes
		((or dom:element dom:document) (dom:child-nodes ,nodes))
		((or list vector) ,nodes))))
       (,kwd ,kid in ,nl))))


(defun xmls-to-dom-snippet ( sxml &key
			    (namespace "http://www.w3.org/1999/xhtml"))
  "Given a snippet of xmls, return a new dom snippet of that content"
  (etypecase sxml
    (string sxml)
    (list (destructuring-bind (tagname attrs . kids) sxml
	    (create-complete-element
	     *document* namespace
	     tagname
	     (iter (for (k v) in attrs) (collect k) (collect v))
	     (loop for node in kids
		   collecting
		   (xmls-to-dom-snippet node :namespace namespace)))))))

(defparameter *xhtml1-transitional-extid*
  (let ((xhtml1-transitional.dtd
          (asdf:system-relative-pathname
           :buildnode "src/xhtml1-transitional.dtd")))
   (cxml:make-extid
    "-//W3C//DTD XHTML 1.0 Transitional//EN"
    (puri:uri
     (cl-ppcre:regex-replace-all
      " "
      #?|file://${xhtml1-transitional.dtd}|
      "%20")))))

(defgeneric text-of-dom-snippet  (el &optional splice stream)
  (:documentation
   "get all of the textnodes of a dom:element and return that string
   with splice between each character")
  (:method  (el &optional splice stream)
    (flet ((body (s)
             (iter
               (with has-written = nil )
               (for node in-dom el)
               (when (dom:text-node-p node)
                 (when (and has-written splice)
                   (princ splice s))
                 (princ (dom:data node) s)
                 (setf has-written T)
                 ))))
      (if stream
          (body stream)
          (with-output-to-string (stream)
            (body stream))))))

(defun join-text (text &key delimiter)
  "Like joins trees of lists strings and dom nodes into a single string possibly with a delimiter
   ignores nil and empty string"
  (collectors:with-string-builder-output
      (%collect :delimiter delimiter)
    (labels ((collect (s)
               (typecase s
                 (null)
                 (list (collector s))
                 ((or string number symbol) (%collect s))
                 (dom:node (%collect (buildnode:text-of-dom-snippet s)))))
             (collector (items)
               (mapcar #'collect (alexandria:ensure-list items))))
      (collector text))))

(defclass scoped-dom-builder (rune-dom::dom-builder)
  ()
  (:documentation
   "A dom builder that builds inside of another dom-node"))
(defmethod sax:start-document ((db scoped-dom-builder)))
(defmethod sax:end-document ((db scoped-dom-builder))
  (rune-dom::document db))

(defmethod sax:unescaped ((builder scoped-dom-builder) data)
  ;; I have no idea how to handle unescaped content in a dom (which is
  ;; probably why this was not implemented on dom-builder)
  ;; we will just make a text node of it for now :/
  ;; other thoughts would be a processing instruction or something
  (buildnode:add-children
   (first (rune-dom::element-stack builder))
   (dom:create-text-node *document* data))
  (values))

;;;; I think we might be able to use this as a dom-builder for a more efficient
;;;; version of the inner-html function
(defun make-scoped-dom-builder (node)
  "Returns a new scoped dom builder, scoped to the passed in node.
   Nodes built with this builder will be added to the passed in node"
  (let ((builder (make-instance 'scoped-dom-builder)))
    (setf (rune-dom::document builder) (etypecase node
					 (dom:document node)
					 (dom:node (dom:owner-document node)))
 	  (rune-dom::element-stack builder) (list node))
    builder))

(defclass html-whitespace-remover (cxml:sax-proxy)
  ()
  (:documentation "a stream filter to remove nodes that are entirely whitespace"))

(defmethod sax:characters ((handler html-whitespace-remover) data)
  (unless (every #'cxml::white-space-rune-p (cxml::rod data)) (call-next-method)))

(defun insert-html-string (string &key
                                  (tag "div")
                                  (namespace-uri "http://www.w3.org/1999/xhtml")
                                  (dtd nil)
                                  (remove-whitespace? t))
  "Parses a string containing a well formed html snippet
   into dom nodes inside of a newly created node.

   (Based loosely around the idea of setting the javascript innerHTML property)

   Will wrap the input in a tag (which is neccessary from CXMLs perspective)
   can validate the html against a DTD if one is passed, can use
   *xhtml1-transitional-extid* for example.
   "
  (handler-bind ((warning #'(lambda (condition)
			      (declare (ignore condition))
			      (muffle-warning))))
    (let ((node (dom:create-element *document* tag)))
      (cxml:parse #?|<${tag} xmlns="${ namespace-uri }">${string}</${tag}>|
		  (if remove-whitespace?
		      (make-instance 'html-whitespace-remover
				     :chained-handler (make-scoped-dom-builder node))
		      (make-scoped-dom-builder node))
		  :dtd dtd)
      (dom:first-child node))))

(defun inner-html (string &optional (tag "div")
                          (namespace-uri "http://www.w3.org/1999/xhtml")
                          (dtd nil)
                          (remove-whitespace? t))
  (insert-html-string
   string :tag tag :namespace-uri namespace-uri :dtd dtd
          :remove-whitespace? remove-whitespace?))

(defun document-of (el)
  "Returns the document of a given node (or the document if passed in)"
  (if (typep el 'rune-dom::document)
      el
      (dom:owner-document el)))

(defun add-children (elem &rest kids
                          &aux
                          (list? (listp elem))
                          (doc (document-of (if list? (first elem) elem)))
                          (elem-list (alexandria:ensure-list elem)))
  "adds some kids to an element and return that element
    alias for append-nodes"
  (iter (for kid in (flatten-children kids doc))
    (when list?
      (setf kid (dom:clone-node kid T)))
    (iter (for e in elem-list)
      (dom:append-child e kid)))
  elem)

(defun insert-children (elem idx &rest kids)
  " insert a bunch of dom-nodes (kids) to the location specified
     alias for insert-nodes"
  (setf kids (flatten-children kids (document-of elem)))
  (if (<= (length (dom:child-nodes elem)) idx )
      (apply #'add-children elem kids)
      (let ((after (elt (dom:child-nodes elem) idx)))
	(iter (for k in kids)
	      (dom:insert-before elem k after))))
  elem)

(defun append-nodes (to-location &rest chillins)
  "appends a bunch of dom-nodes (chillins) to the location specified
   alias of add-children"
  (apply #'add-children to-location chillins))

(defun insert-nodes (to-location index &rest chillins)
  "insert a bunch of dom-nodes (chillins) to the location specified
    alias of insert-children"
  (apply #'insert-children to-location index chillins))

(defvar *html-compatibility-mode* nil)
(defvar *cdata-script-blocks* T "Should script blocks have a cdata?")
(defvar *namespace-prefix-map*
  '(("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" . "xul")
    ("http://www.w3.org/1999/xhtml" . "xhtml")))

(defun get-prefix (namespace &optional (namespace-prefix-map
					*namespace-prefix-map*))
  (when namespace-prefix-map
  (the (or null string)
    (cdr (assoc namespace namespace-prefix-map :test #'string=)))))

(defun get-namespace-from-prefix (prefix &optional (namespace-prefix-map
						    *namespace-prefix-map*))
  (when namespace-prefix-map
    (the (or null string)
      (car (find prefix namespace-prefix-map :key #'cdr :test #'string=)))))

(defun calc-complete-tagname (namespace base-tag namespace-prefix-map)
  (let ((prefix
	 (and namespace-prefix-map
	      (not (cxml::split-qname base-tag)) ;not already a prefix
	      (let ((prefix (get-prefix namespace namespace-prefix-map)))
		;;found the given namespace in the map
		(when (and prefix (> (length (the string prefix)) 0))
		  prefix)))))
    (if prefix
	#?"${prefix}:${base-tag}"
	base-tag)))

(defun prepare-attribute-name (attribute)
  "Prepares an attribute name for output to html by coercing to strings"
  (etypecase attribute
    (symbol (coerce (string-downcase attribute)
		    '(simple-array character (*))))
    (string attribute)))

(defun prepare-attribute-value (value)
  "prepares a value for html out put by coercing to a string"
  (typecase value
    (string value)
    (symbol (string-downcase (symbol-name value)))
    (T (princ-to-string value))))

(defun attribute-uri (attribute)
  (typecase attribute
    (symbol nil)
    (string
       (let ((list (cl-ppcre:split ":" attribute)))
	 (case (length list)
	   (2 (get-namespace-from-prefix (first list)))
	   ((0 1) nil)
	   (T (error "Couldnt parse attribute-name ~a into prefix and name" attribute)))))))

(defgeneric get-attribute (elem attribute)
  (:documentation
   "Gets the value of an attribute on an element
   if the attribute does not exist return nil
  ")
  (:method (elem attribute)
    (when elem
      (let ((args (list elem
                        (attribute-uri attribute)
                        (prepare-attribute-name attribute))))
        (when (apply #'dom:has-attribute-ns args)
          (apply #'dom:get-attribute-ns args))))))

(defgeneric set-attribute (elem attribute value)
  (:documentation "Sets an attribute and passes the elem through, returns the elem. If value is nil, removes the attribute")
  (:method (elem attribute value)
    (iter
      (with attr = (prepare-attribute-name attribute))
      (for e in (alexandria:ensure-list elem))
      (if value
          (dom:set-attribute-ns e (attribute-uri attribute)
                                attr (prepare-attribute-value value))
          (alexandria:when-let ((it (dom:get-attribute-node e attr)))
            (dom:remove-attribute-node e it))))
    elem))

(defgeneric remove-attribute (elem attribute)
  (:documentation
   "removes an attribute and passes the elem through, returns the elem
   If the attribute does not exist, simply skip it
  ")
  (:method (elem attribute)
    ;; throws errors to remove attributes that dont exist
    ;; dont care about that
    (iter (for e in (alexandria:ensure-list elem))
      (let ((uri (attribute-uri attribute))
            (name (prepare-attribute-name attribute)))
        (when (dom:has-attribute-ns e uri name)
          (dom:remove-attribute-ns e uri name))))
    elem))

(defun remove-attributes (elem &rest attributes)
  "removes an attribute and passes the elem through, returns the elem"
  (iter (for attr in attributes)
	(remove-attribute elem attr))
  elem)

(defgeneric css-classes ( o )
  (:documentation
   "Returns a list of css classes (space separated names in the 'class' attribute)")
  (:method (o)
    (etypecase o
      (null)
      (string (split-sequence:split-sequence #\space o :remove-empty-subseqs t))
      (dom:element (css-classes (get-attribute o :class))))))

(defgeneric add-css-class (element new-class)
  (:documentation
   "Adds a new css class to the element and returns the element")
  (:method  ((el dom:element) new-class
             &aux (new-class (trim-and-nullify new-class)))
    (when new-class
      (let* ((class-string (get-attribute el :class))
             (regex #?r"(?:$|^|\s)*${new-class}(?:$|^|\s)*"))
        (unless (cl-ppcre:scan regex class-string)
          (set-attribute el :class (format nil "~@[~a ~]~a" class-string new-class)))))
    el))

(defgeneric add-css-classes (comp &rest classes)
  (:method (comp &rest classes)
    (declare (dynamic-extent classes))
    (iter (for class in classes) (add-css-class comp class))
    comp))

(defgeneric remove-css-class (el new-class)
  (:documentation "Removes a css class from the elements and returns the element")
  (:method ((el dom:element) new-class)
    (let* ((class-string (get-attribute el :class))
           (regex #?r"(?:$|^|\s)*${new-class}(?:$|^|\s)*")
           (new-class-string (trim-and-nullify (cl-ppcre:regex-replace-all regex class-string " "))))
      (if new-class-string
          (set-attribute el :class new-class-string)
          (remove-attribute el :class))
      el)))

(defgeneric remove-css-classes ( comp &rest classes)
  (:method (comp &rest classes)
    (declare (dynamic-extent classes))
    (iter (for class in classes) (remove-css-class comp class))
    comp))

(defun push-new-attribute (elem attribute value)
  "if the attribute is not on the element then put it there with the specified value,
   returns the elem and whether or not the attribute was set"
  (values elem
   (when (null (get-attribute elem attribute))
     (set-attribute elem attribute value)
     T)))

(defun push-new-attributes (elem &rest attribute-p-list)
  "for each attribute in the plist push-new into the attributes list of the elem, returns the elem"
  (iter (for (attr val) on attribute-p-list by #'cddr)
	(push-new-attribute elem attr val))
  elem)

(defun set-attributes (elem &rest attribute-p-list)
  "set-attribute for each attribute specified in the plist, returns the elem"
  (iter (for (attr val) on attribute-p-list by #'cddr)
	(set-attribute elem attr val))
  elem)

(defun create-complete-element (document namespace tagname attributes children
					 &optional
				(namespace-prefix-map *namespace-prefix-map*))
  "Creates an xml element out of all the necessary components.
If the tagname does not contain a prefix, then one is added based on the namespace-prefix map."
  (declare (type list attributes))
  ;;if we don't already have a prefix and we do find one in the map.
  (let* ((tagname (if namespace-prefix-map
		      (calc-complete-tagname namespace tagname namespace-prefix-map)
		      tagname))
	 (elem (dom:create-element-ns document namespace tagname)))
    (when (oddp (length attributes))
      (error "Incomplete attribute-value list. Odd number of elements in ~a" attributes))
    (apply #'set-attributes elem attributes)
    ;;append the children to the element.
    (append-nodes elem children)
    elem))


(defun write-normalized-document-to-sink (document stream-sink)
  "writes a cxml:dom document to the given stream-sink,
passing the document through a namespace normalizer first, and
possibly a html-compatibility-sink if *html-compatibility-mode* is set"
  (dom-walk
   (cxml:make-namespace-normalizer stream-sink)
   document
   :include-doctype :canonical-notations))

;; HACK to make CHTML output html5 style doctypes
(defclass html5-capable-character-output-sink (chtml::sink)
  ())

(defun html5-capable-character-output-sink (stream &key canonical indentation encoding)
  (declare (ignore canonical indentation))
  (let ((encoding (or encoding "UTF-8"))
        (ystream #+rune-is-character
                 (chtml::make-character-stream-ystream stream)
                 #-rune-is-character
                 (chtml::make-character-stream-ystream/utf8 stream)
                 ))
    (setf (chtml::ystream-encoding ystream)
          (runes:find-output-encoding encoding))
    (make-instance 'html5-capable-character-output-sink
                   :ystream ystream
                   :encoding encoding)))

(defmethod hax:start-document ((sink html5-capable-character-output-sink) name public-id system-id)
  (closure-html::sink-write-rod #"<!DOCTYPE " sink)
  (closure-html::sink-write-rod name sink)
  (cond
    ((plusp (length public-id))
     (closure-html::sink-write-rod #" PUBLIC \"" sink)
     (closure-html::unparse-string public-id sink)
     (closure-html::sink-write-rod #"\" \"" sink)
     (closure-html::unparse-string system-id sink)
     (closure-html::sink-write-rod #"\"" sink))
    ((plusp (length system-id))
     (closure-html::sink-write-rod #" SYSTEM \"" sink)
     (closure-html::unparse-string system-id sink)
     (closure-html::sink-write-rod #"\"" sink)))
  (closure-html::sink-write-rod #">" sink)
  (closure-html::sink-write-rune #/U+000A sink))

(defun make-output-sink (stream &key canonical indentation (char-p T))
  (apply
   (cond
     ((and char-p *html-compatibility-mode*)
      #'html5-capable-character-output-sink)
     ((and (not char-p) *html-compatibility-mode*)
      #'chtml:make-octet-stream-sink)
     ((and char-p (not *html-compatibility-mode*))
      #'cxml:make-character-stream-sink)
     ((and (not char-p) (not *html-compatibility-mode*))
      #'cxml:make-octet-stream-sink))
   stream
   (unless *html-compatibility-mode*
     (list :canonical canonical :indentation indentation))))

(defun write-document-to-character-stream (document char-stream)
  "writes a cxml:dom document to a character stream"
  (let ((sink (make-output-sink char-stream)))
    (write-normalized-document-to-sink document sink)))

(defun write-document-to-octet-stream (document octet-stream)
  "writes a cxml:dom document to a character stream"
  (let ((sink (make-output-sink octet-stream :char-p nil)))
    (write-normalized-document-to-sink document sink)))

(defgeneric html-output? (doc)
  (:method (doc)
    (let ((dt (dom:doctype doc)))
      (or *html-compatibility-mode*
          (and
           dt
           (string-equal "html" (dom:name dt))
           (not (search "xhtml" (dom:system-id dt) :test #'string-equal)))))))

(defun write-document (document &optional (out-stream *standard-output*))
  "Write the document to the designated out-stream, or *standard-ouput* by default."
  (let ((*html-compatibility-mode* (html-output? document)))
    (case (stream-element-type out-stream)
      ('character (write-document-to-character-stream document out-stream))
      (otherwise (write-document-to-octet-stream document out-stream)))))

(defmacro with-document (&body chillins)
  "(with-document ( a bunch of child nodes of the document )) --> cxml:dom document
Creates an environment in which the special variable *document* is available
a document is necessary to create dom nodes and the document the nodes end up on
must be the document on which they were created.  At the end of the form, the
complete document is returned"
  `(let ((*document*  (cxml-dom:create-document)))
    (append-nodes *document* ,@chillins)
    *document*))

(defmacro with-document-to-file (filename &body chillins)
  "Creates a document block with-document upon which to add the chillins (southern for children).
  When the document is complete, it is written out to the specified file."
  `(write-doc-to-file (with-document ,@chillins) ,filename))

(defun write-doc-to-file (doc filename)
  "Binary write-out a document. will create/overwrite any existing file named the same."
  (let ((filename (merge-pathnames filename)) )
    (with-open-stream (fd (open filename :direction :output :element-type '(unsigned-byte 8)
							    :if-does-not-exist :create
							    :if-exists :supersede))
      (write-document doc fd))
    (values doc filename)))

(defun document-to-string (doc)
  "Return a string representation of a document."
  (with-output-to-string (fd)
    (write-document doc fd)))

(defmacro with-xhtml-document (&body chillins)
  "(with-xhtml-document ( a bunch of child nodes of the document )) --> cxml:dom document
Creates an environment in which the special variable *document* is available
a document is necessary to create dom nodes and the document the nodes end up on
must be the document on which they were created.  At the end of the form, the
complete document is returned.
This sets the doctype to be xhtml transitional."
  `(let ((*cdata-script-blocks* T)
	 (*document* (dom:create-document
		      'rune-dom:implementation
		      nil nil
		      (dom:create-document-type
		       'rune-dom:implementation
		       "html"
		       "-//W3C//DTD XHTML 1.0 Transitional//EN"
		       "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"))))
    (append-nodes *document* ,@chillins)
    *document*))

(defmacro with-xhtml-frameset-document (&body chillins)
  "(with-xhtml-document ( a bunch of child nodes of the document )) --> cxml:dom document
Creates an environment in which the special variable *document* is available
a document is necessary to create dom nodes and the document the nodes end up on
must be the document on which they were created.  At the end of the form, the
complete document is returned.
This sets the doctype to be xhtml transitional."
  `(let ((*document* (dom:create-document
		      'rune-dom:implementation
		      nil nil
		      (dom:create-document-type
		       'rune-dom:implementation
		       "html"
		       "-//W3C//DTD XHTML 1.0 Frameset//EN"
		       "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd"))))
    (append-nodes *document* ,@chillins)
    *document*))

(defmacro with-xhtml-document-to-file (filename &body chillins)
  "Creates a document block with-document upon which to add the chillins (southern for children).  When the document is complete, it is written out to the specified file."
  `(write-doc-to-file (with-xhtml-document ,@chillins) ,filename))


(defmacro with-html-document-to-file ((filename) &body body)
  "Creates an html-document, writes out the results to filename"
  `(let ((*html-compatibility-mode* T))
    (write-doc-to-file (with-html-document ,@body)
		      ,filename)))

(defmacro with-html-document (&body body)
  "(with-html-document ( a bunch of child nodes of the document )) --> cxml:dom document
Creates an environment in which the special variable *document* is available
a document is necessary to create dom nodes and the document the nodes end up on
must be the document on which they were created.  At the end of the form, the
complete document is returned.
This sets the doctype to be html 4.01 strict."
  `(let ((*namespace-prefix-map* nil)
	 (*document* (dom:create-document
		      'rune-dom:implementation
		      nil nil
		      (dom:create-document-type
		       'rune-dom:implementation
		       "html"
		       "-//W3C//DTD HTML 4.01//EN"
		       "http://www.w3.org/TR/html4/strict.dtd")
		      ))
	 (*html-compatibility-mode* T)
	 (*cdata-script-blocks* nil))
    (declare (special *document*))
    (append-nodes *document* ,@body)
    *document*))

(defmacro with-html5-document-to-file ((filename) &body body)
  "Creates an html-document, writes out the results to filename"
  `(let ((*html-compatibility-mode* T))
    (write-doc-to-file (with-html5-document ,@body)
     ,filename)))

(defmacro with-html5-document (&body body)
  "(with-html5-document ( a bunch of child nodes of the document )) --> cxml:dom document
Creates an environment in which the special variable *document* is available
a document is necessary to create dom nodes and the document the nodes end up on
must be the document on which they were created.  At the end of the form, the
complete document is returned.
This sets the doctype to be html5 compatible <!DOCTYPE html>."
  `(let ((*namespace-prefix-map* nil)
	 (*document* (dom:create-document
		      'rune-dom:implementation
		      nil nil
		      (dom:create-document-type
		       'rune-dom:implementation
		       "html"
		       nil
		       nil)
		      ))
	 (*html-compatibility-mode* T)
	 (*cdata-script-blocks* nil))
    (declare (special *document*))
    (append-nodes *document* ,@body)
    *document*))

(defmacro with-html-document-to-string (() &body body)
  "trys to output a string containing all "
  `(let ((*html-compatibility-mode* T))
     (document-to-string (with-html-document ,@body))))

(defmacro with-html5-document-to-string (() &body body)
  "trys to output a string containing all "
  `(let ((*html-compatibility-mode* T))
     (document-to-string (with-html5-document ,@body))))

(defgeneric remove-all-children (el)
  (:method ((it dom:element))
    ;; should be a touch faster than removing one at a time
    (iter (for n in-dom-children it)
      (setf (slot-value n 'rune-dom::parent) nil))
    (setf (slot-value it 'rune-dom::children) (rune-dom::make-node-list))
    it))

(defvar *snippet-output-stream* nil)

(defun %enstream (stream content-fn)
  (let* ((old-out-stream *snippet-output-stream*)
         (*snippet-output-stream* (or stream (make-string-output-stream )))
         (result (multiple-value-list (funcall content-fn))))
    (cond
      (stream (apply #'values result))
      (old-out-stream
       (write-string (get-output-stream-string *snippet-output-stream*) old-out-stream))
      (t (get-output-stream-string *snippet-output-stream*)))))

(defun %buffer-xml-output (stream sink body-fn)
  (let ((cxml::*sink* (or sink (make-character-stream-sink stream)))
        (cxml::*current-element* nil)
        (cxml::*unparse-namespace-bindings* cxml::*initial-namespace-bindings*)
        (cxml::*current-namespace-bindings* nil))
    (setf (cxml::sink-omit-xml-declaration-p cxml::*sink*) T)
    (sax:start-document cxml::*sink*)
    (funcall body-fn)
    (sax:end-document cxml::*sink*)))

(defmacro buffer-xml-output ((&optional stream sink) &body body)
  "buffers out sax:events to a sting

   xml parameters like <param:foo param:type=\"string\"><div>bar</div></param:foo>
       are requested to be strings (presumably for string processing)
  "
  (let ((content `(lambda () (%buffer-xml-output *snippet-output-stream* ,sink (lambda () ,@body)))))
    `(%enstream ,stream ,content)))

(defmacro %with-snippet ((type &optional stream sink) &body body)
  "helper to define with-html-snippet and with-xhtml-snippet"
  (assert (member type '(with-html-document with-xhtml-document)))
  (alexandria:with-unique-names (result)
  `(let ((*html-compatibility-mode* ,(eql type 'with-html-document))
         ,result)
    (,type
     (progn
       (setf
        ,result
        (multiple-value-list
         (buffer-xml-output (,stream ,sink)
           (let ((content (flatten-children (progn ,@body))))
             (iter (for n in content)
               (buildnode::dom-walk cxml::*sink* n))))))
       nil))
    (apply #'values ,result))))

(defmacro with-html-snippet ((&optional stream sink) &body body)
  "builds a little piece of html-dom and renders that to a string / stream"
  `(%with-snippet (with-html-document ,stream ,sink) ,@body))

(defmacro with-xhtml-snippet ((&optional stream sink) &body body)
  "builds a little piece of xhtml-dom and renders that to a string / stream"
  `(%with-snippet (with-xhtml-document ,stream ,sink) ,@body))

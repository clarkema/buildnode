(in-package :buildnode-test)
(cl-interpol:enable-interpol-syntax)

(buildnode-w/doc-test test-flatten-&-iter-dom-children (dom-manipulation iter)
  (assert-equal
   7
   (length (flatten-children (list
			      (list (xhtml:div () (xhtml:div ()))
				    (xhtml:div ()))
			      (dom:child-nodes (xhtml:div () (xhtml:div () (xhtml:div ()))))
			      (xhtml:span ())
			      "47.3"
			      42.02d0
			      3)
			     *document*))))

(defun tag-sym (n)
  (typecase n
    (dom:element
       (intern (string-upcase (dom:tag-name n)) :keyword))))

(buildnode-w/doc-test test-iter-parents (dom-manipulation iter)
  (let* (it
	 (n (xhtml:div ()
	      (xhtml:span ()
		"span 1"
		(xhtml:label ()
		  "inner"
		  (xhtml:label ()
		    (xhtml:span ()
		      (xhtml:div ())
		      (setf it (xhtml:div () "target"))))))
	      (xhtml:span () "span 2" (xhtml:div ()))
	      (xhtml:span () "span 3"))))
    (declare (ignore n))
    (iter (for node in-dom-parents it)
	  (for tag = (tag-sym node))
	  ;(break "~A:~A" tag node)
	  (when (first-iteration-p)
	    (assert-eql :span tag ))
	  (case tag
	    (:span (count tag into spans))
	    (:div (count tag into divs))
	    (:label (count tag into labels)))
	  (finally
	   (assert-eql 2 spans )
	   (assert-eql 1 divs )
	   (assert-eql 2 labels)))
    ))

(buildnode-w/doc-test test-iter-children (dom-manipulation iter)
  (let ((t1 (list
	     (vector
	      (xhtml:div ()
		(xhtml:span ()
		  "span 1"
		  (xhtml:label () "inner"))
		(xhtml:span () "span 2")
		(xhtml:span () "span 3"))
	      (xhtml:span ()))
	     (xhtml:span ())
	     (xhtml:div () (xhtml:label ()))))
	(t2 (xhtml:div ()
	      (xhtml:span () (xhtml:span () (xhtml:span () (xhtml:span ()))))
	      (xhtml:label ())
	      (xhtml:span ())
	      (xhtml:label ())
	      (xhtml:span ())
	      (xhtml:label ()))))
    (iter (for node in-dom-children t1)
	  (for tag = (tag-sym node))
	  (case tag
	    (:span (count tag into spans))
	    (:div (count tag into divs))
	    (:label (count tag into labels)))
	  (finally
	   (assert-eql 2 spans )
	   (assert-eql 2 divs )
	   (assert-eql 0 labels)))
    (iter (for node in-dom-children t2)
	  (for tag = (tag-sym node))
	  (case tag
	    (:span (count tag into spans))
	    (:div (count tag into divs))
	    (:label (count tag into labels)))
	  (finally
	   (assert-eql 3 spans )
	   (assert-eql 0 divs )
	   (assert-eql 3 labels)))
    ))

(buildnode-w/doc-test test-iter-nodes (dom-manipulation iter)
  (let* ((t1 (xhtml:div ()
	       (xhtml:span ()
		 "span 1"
		 (xhtml:label () "inner"))
	       (xhtml:span () "span 2")
	       (xhtml:span ()
		 "span 3"
		 (xhtml:span ()
		   (xhtml:span ())
		   (xhtml:div ()))))
	   )
	 (t2 (list (vector t1 t1)
		   (list (list (list t1))))
	   ))
    (iter (for node in-dom t1)
	  (for tag = (tag-sym node))
	  (case tag
	    (:span (count tag into spans))
	    (:div (count tag into divs))
	    (:label (count tag into labels)))
	  (finally
	   (assert-eql 5 spans )
	   (assert-eql 2 divs )
	   (assert-eql 1 labels)))
    (iter (for node in-dom t2)
	  (for tag = (tag-sym node))
	  (case tag
	    (:span (count tag into spans))
	    (:div (count tag into divs))
	    (:label (count tag into labels)))
	  (finally
	   (assert-eql 15 spans )
	   (assert-eql 6 divs )
	   (assert-eql 3 labels)))))

(buildnode-w/doc-test test-add-chilren (dom-manipulation)
  (let ((node (xhtml:div ())))
    (add-children node
		  (list (xhtml:div () (xhtml:div ()))
			(xhtml:div ()))
		  (dom:child-nodes (xhtml:div () (xhtml:div () (xhtml:div ()))))
		  (xhtml:span ())
		  "47.3"
		  42.02d0
		  3)
    (assert-equal
     7
     (length (dom:child-nodes node)))))

(buildnode-w/doc-test attrib-manip (dom-manipulation)
  (let ((node (xhtml:div ())))
    (assert-eql nil (get-attribute node :test))
    (set-attribute node :test "test-value" )
    (assert-equal "test-value" (get-attribute node :test))
    (remove-attributes node :test :test2 :test3)
    (remove-attribute node :test) ;; test this doesnt error on non-existance
    (assert-eql nil (get-attribute node :test))
    (set-attribute node :test 2 )
    (assert-equal (prepare-attribute-value 2)
		  (get-attribute node :test))

    (set-attribute node :test :foo-bar-bast )
    (assert-equal (prepare-attribute-value :foo-bar-bast)
		  (get-attribute node :test))
    (push-new-attribute node :test :a-new-value)
    (assert-equal (prepare-attribute-value :foo-bar-bast)
		  (get-attribute node :test))
    (remove-attribute node :test)
    (push-new-attribute node :test :a-new-value)
    (assert-equal (prepare-attribute-value :a-new-value)
		  (get-attribute node :test))

    (push-new-attributes node :test :a-newer-value :test2 :also-a-value)
    (assert-equal (prepare-attribute-value :a-new-value)
		  (get-attribute node :test))
    (assert-equal (prepare-attribute-value :also-a-value)
		  (get-attribute node :test2))
    
    ))

(buildnode-w/doc-test class-manip (dom-manipulation)
  (let ((node (xhtml:div ())))
    (flet ((diff (&rest vals)
	     (set-exclusive-or vals (css-classes node) :test #'string=)))
      (assert-eql nil (css-classes node))
      (add-css-class node "test")
      (assert-eql nil (diff "test"))
      (add-css-class node "test2")
      (assert-eql nil (diff "test2" "test"))
      (add-css-class node "TEST3")
      (assert-eql nil (diff "test2" "test" "TEST3"))
      (remove-css-class node "test2")
      (assert-eql nil (diff "test" "TEST3"))
      (remove-css-class node "test")
      (remove-css-class node "TEST3")
      (assert-eql nil (get-attribute node :class))
      (assert-eql nil (css-classes node))
      )))

(buildnode-w/doc-test test-insert-chilren (dom-manipulation)
  (let ((node (xhtml:div ()
		(xhtml:div '(:class "first"))
		(xhtml:div '(:class "last")))))
    (insert-children
     node 1
     (xhtml:div ())
     (xhtml:span ())
     "47.3"
     42.02d0
     3)
    (assert-equal
     7
     (length (dom:child-nodes node)))
    (assert-equalp "first"
		   (get-attribute (dom:first-child node) :class))
    (assert-equalp "last" 
		   (get-attribute (dom:last-child node) :class))
    ))

(buildnode-test test-basic-html-doc (render)
  ;; Not a great test, but a basic, does everything seem correct.
  ;; Manually verify the html is as expected, so that this will mostly just
  ;; detect when soemthing changes output
  (assert-equalp
   "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">
<div><span class=\"test test2\" test=\"1\" title=\"test\">42.02</span>this is a test<br></div>"
   (with-html-document-to-string ()
     (xhtml:div ()
       (add-css-class
	(set-attributes
	 (xhtml:span () 42.02)
	 :title "test"
	 :test 1
	 :class "test")
	"test2")
       "this is a test"
       (xhtml:br)
       ))))

(buildnode-w/doc-test test-text-of-dom (dom-manipulation)
  (let* ((node (xhtml:div () "This is a test"
			  (xhtml:span () " of the text")
			  (xhtml:ul ()
			    (xhtml:li () " you")
			    (xhtml:li () " should")
			    (xhtml:li () " find"))))
	 (out (text-of-dom-snippet node))
	 (out2 (text-of-dom-snippet node "|")))
    (assert-equal "This is a test of the text you should find"
		  out)
    (assert-equal "This is a test| of the text| you| should| find"
		  out2)
    ))

(buildnode-w/doc-test test-inner-html (dom-manipulation)
  (let* ((node (inner-html "<span class=\"some-class\">A classy spans text</span>")))
    (assert-equal "A classy spans text"
		  (text-of-dom-snippet node))
    (assert-equal "some-class"
		  (get-attribute (dom:first-child node) :class))
    ))

(buildnode-test test-document-to-string (utils)
  (let* ((it "<head id=\"head\" class=\"header\"><title>Title</title></head><body>Our Body</body>")
	 (doc (with-xhtml-document
		(inner-html it "html")))
	 (ds (document-to-string doc)))
    (assert-true
     (search it ds :test #'string-equal)
     it ds doc)
    
    ))

(buildnode-test test-attribute-order (utils)
  (let* ((it "<head id=\"head\" class=\"header\" foo=\"my-attrib\"><title>Title</title></head><body>Our Body</body>")
	 (doc (with-xhtml-document
		(inner-html it "html")))
	 (ds (document-to-string doc))
	 (doc2 (with-xhtml-document
		 (set-attributes
		  (xhtml:html '(:class "my-class" :id "my-id" :foo "my-attrib"))
		  :bar "my-attib2")))
	 (ds2 (document-to-string doc2)))
    (assert-true
     (search it ds :test #'string-equal)
     it ds doc)
    ;; TODO: Figure out how to get attribute ordering correct 
    (let (;(it "class=\"my-class\" id=\"my-id\" foo=\"my-attrib\" bar=\"my-attib2\"")
	  (it "bar=\"my-attib2\" foo=\"my-attrib\" id=\"my-id\" class=\"my-class\""))
      (assert-true
       (search it ds2 :test #'string-equal)
       it ds2 doc2))
    
    ))

(buildnode-test test-join-text (utils)
  (let* ((doc (with-xhtml-document
		(xhtml:span () "test")))
	 (tree `("3" ("2" ("1" ,doc) "1") "2" "3")))
    (assert-equal "3 2 1 test 1 2 3" (join-text tree :delimiter " "))))

(buildnode-w/doc-test test-add/remove-class (dom-manipulation)
  (let ((node (xhtml:div '(:class "class1")))
        (n2 (xhtml:div '())))
    (add-css-classes node "class2" nil "class3" )
    (assert-equal "class1 class2 class3" (get-attribute node :class))
    (assert-equal '("class1" "class2" "class3") (css-classes node))
    (remove-css-classes node "class1" "class3")
    (assert-equal "class2" (get-attribute node :class))
    (assert-equal '("class2") (css-classes node))
    (assert-false (css-classes n2))
    (add-css-class n2 "class1")
    (assert-equal "class1" (get-attribute n2 :class))
    (add-css-class n2 "class2")
    (assert-equal "class1 class2" (get-attribute n2 :class))
    (remove-css-class n2 "class1")
    (assert-equal "class2" (get-attribute n2 :class))))



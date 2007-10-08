(in-package :2d-geometry)

;;;; This files contains function for trapeziodation  of complex polygons, with the ultimate goal of
;;;; decomposing them  into simple,  disjoint polygons  (trapezoids, which can  be joined  back into
;;;; larger polygons if desired, albeit slowly).

;;;; This is somewhat different that trapezoidation for efficient triangulation, but it may be possible to
;;;; modify this code to do that. That is, it will work, but it may or may be not faster than ear removal.

(defun orient-edge-right (edge)
  "Returns an edge oriented up. It makes a new object event if argument is already up."
  (if (> (x (start edge))(x (end edge)))
      (make-instance 'line-segment
		     :start (end edge)
		     :end (start edge))
      (make-instance 'line-segment
		     :start (start edge)
		     :end (end edge))))

(defun vertical-edge (edge)
  "Returns t if edge is horizontal."
  (= (x (start edge))(x (end edge))))

(defun trapezoidize-edges (edge-list)
  "Returns a list of trapezoids build from a set of edges and their bounding box."
  (let ((clean-edge-list (mapcar #'orient-edge-right (remove-if #'vertical-edge edge-list))))
    ;vertical edges only create problems when trapezoidating
    (let ((endpoints (create-initial-event-list clean-edge-list))
	  (intersections (bentley-ottmann clean-edge-list)))
      (destructuring-bind (min-y . max-y)
	  (iterate (for i in endpoints)
		   (maximizing (y i) into max-y)
		   (minimizing (y i) into min-y)
		   (finally (return (cons min-y max-y))))
	(let ((event-queue (sort (append endpoints intersections) #'point-sort-fun))
	      (sweep-line (make-instance 'sweep-line))
	      (trapezoids nil))
	  ;init sweep-line
	  (let ((init-x (x (car event-queue))))
	    (iterate (while (and event-queue
				 (= (x (car event-queue)) init-x)))
		     (let ((event (pop event-queue)))
		       (move-sweep-line sweep-line (x event)(y event))
		       (insert-edge (edge event) sweep-line))))
	  (iterate (while event-queue)
		   ;generate trapezoids
		   (let ((prev-edge (make-instance 'line-segment
						   :start
						   (make-instance 'point
								  :x (x sweep-line)
								  :y max-y)
						   :end
						   (make-instance 'point
								  :x (x (car event-queue))
								  :y max-y)))
			 (event (car event-queue)))
		     (trees:dotree (tk (edge-tree sweep-line))
		       ;ignore edges on bounding box
		       (unless (or (and (= (y (start tk)) min-y)
					(= (y (end tk)) min-y))
				   (and (= (y (start tk)) max-y)
					(= (y (end tk)) max-y)))
			 (let ((inters1-y (y (lines-intersection-point
					     (line-from-segment tk)
					     (make-instance 'line :a 1 :b 0 :c (- (x event))))))
			       (inters2-y (y (lines-intersection-point
					      (line-from-segment prev-edge)
					      (make-instance 'line :a 1 :b 0 :c (- (x event)))))))
			   (push (coords-to-points
				  (list (x sweep-line)(y (start prev-edge))
					(x event) inters2-y
					(x event) inters1-y
					(x sweep-line)(y (start tk))))
				 trapezoids))
			 (setf prev-edge tk)))
		     ;terminate with upper bounding edge
		     (push (coords-to-points
			    (list (x sweep-line)(y (start prev-edge))
				  (x event)(y (lines-intersection-point
					       (line-from-segment prev-edge)
					       (make-instance 'line :a 1 :b 0 :c (- (x event)))))
				  (x event) min-y
				  (x sweep-line) min-y))
			   trapezoids)
		     ;truncate edges
		     (trees::dotree (tk (edge-tree sweep-line))
		       (unless (= (x event)
				  (x (end tk)))
			 (let ((inters-y (y (lines-intersection-point
					     (line-from-segment tk)
					     (make-instance 'line :a 1 :b 0 :c (- (x event)))))))
			   (setf (start tk)
				 (make-instance 'point
						:x (x event)
						:y inters-y))))))
		   ;shift sweep line
		   (let ((new-x (x (car event-queue))))
		     (iterate (while (and event-queue
					  (= (x (car event-queue)) new-x)))
			      (for event next (pop event-queue))
			      (etypecase event
				(event-endpoint
				 (case (direction event)
				   (right
				    (delete-edge (edge event) sweep-line)
				    (unless (or (null event-queue)
						(point-equal-p (car event-queue) event))
				      (move-sweep-line sweep-line (x event)(y event))))
				   (left
				    (move-sweep-line sweep-line (x event)(y event))
				    (insert-edge (edge event) sweep-line))))
				(event-intersection
				 (delete-edge (edge1 event) sweep-line)
				 (delete-edge (edge2 event) sweep-line)
				 (move-sweep-line sweep-line (x event)(y event))
				 (insert-edge (edge1 event) sweep-line)
				 (insert-edge (edge2 event) sweep-line))))))
	(nreverse trapezoids))))))

(defun collapse-trapezoid (trapezoid)
  "Reduce degenerate trapezoids to triangles."
  (remove-duplicates trapezoid :test #'point-equal-p))

(defun split-trapezoid (trapezoid)
  "Split trapezoid into two triangles. Return a cons."
  (destructuring-bind (v1 v2 v3 v4) trapezoid
    (cons (list v1 v2 v3)
	  (list v3 v4 v1))))

(defun decompose-complex-polygon-triangles (polygon &key (in-test 'point-in-polygon-winding-p))
  "Decomposes a complex polygon into triangles. Returns a list of triangles inside polygon according to :in-test, which is a function taking a point and a polygon."
  (let ((trapez (trapezoidize-edges (edge-list-from-point-list polygon))))
    (let ((triangles nil))
      (dolist (tk trapez)
	(let ((ctrap (collapse-trapezoid tk)))
	  (cond
	    ((= (length ctrap) 3)
	     (push ctrap triangles))
	    ((= (length ctrap) 4)
	     (destructuring-bind (tr1 . tr2) (split-trapezoid ctrap)
	       (push tr1 triangles)
	       (push tr2 triangles))))))
      (remove-if-not #'(lambda (x)
			 (destructuring-bind (a b c) x
			   (let ((central-point (make-instance 'point
							       :x (/ (+ (x a)(x b)(x c)) 3)
							       :y (/ (+ (y a)(y b)(y c)) 3))));possibly overkill, but central point definitely is inside triangle
			     (funcall in-test central-point polygon))))
		     triangles))))
part of dart_jts;

/**
 * A ring of {@link DirectedEdge}s which may contain nodes of degree &gt; 2.
 * A <tt>MaximalEdgeRing</tt> may represent two different spatial entities:
 * <ul>
 * <li>a single polygon possibly containing inversions (if the ring is oriented CW)
 * <li>a single hole possibly containing exversions (if the ring is oriented CCW)
 * </ul>
 * If the MaximalEdgeRing represents a polygon,
 * the interior of the polygon is strongly connected.
 * <p>
 * These are the form of rings used to define polygons under some spatial data models.
 * However, under the OGC SFS model, {@link MinimalEdgeRing}s are required.
 * A MaximalEdgeRing can be converted to a list of MinimalEdgeRings using the
 * {@link #buildMinimalRings() } method.
 *
 * @version 1.7
 * @see org.locationtech.jts.operation.overlay.MinimalEdgeRing
 */
class MaximalEdgeRing extends EdgeRing {
  MaximalEdgeRing(DirectedEdge start, GeometryFactory geometryFactory)
      : super(start, geometryFactory);

  DirectedEdge getNext(DirectedEdge de) {
    return de.getNext();
  }

  void setEdgeRing(DirectedEdge de, EdgeRing er) {
    de.setEdgeRing(er);
  }

  /**
   * For all nodes in this EdgeRing,
   * link the DirectedEdges at the node to form minimalEdgeRings
   */
  void linkDirectedEdgesForMinimalEdgeRings() {
    DirectedEdge de = startDe;
    do {
      Node node = de.getNode();
      (node.getEdges() as DirectedEdgeStar).linkMinimalDirectedEdges(this);
      de = de.getNext();
    } while (de != startDe);
  }

  List buildMinimalRings() {
    List minEdgeRings = [];
    DirectedEdge de = startDe;
    do {
      if (de.getMinEdgeRing() == null) {
        EdgeRing minEr = new MinimalEdgeRing(de, geometryFactory);
        minEdgeRings.add(minEr);
      }
      de = de.getNext();
    } while (de != startDe);
    return minEdgeRings;
  }
}

/**
 * A ring of {@link Edge}s with the property that no node
 * has degree greater than 2.  These are the form of rings required
 * to represent polygons under the OGC SFS spatial data model.
 *
 * @version 1.7
 * @see org.locationtech.jts.operation.overlay.MaximalEdgeRing
 */
class MinimalEdgeRing extends EdgeRing {
  MinimalEdgeRing(DirectedEdge start, GeometryFactory geometryFactory)
      : super(start, geometryFactory);

  DirectedEdge getNext(DirectedEdge de) {
    return de.getNextMin();
  }

  void setEdgeRing(DirectedEdge de, EdgeRing er) {
    de.setMinEdgeRing(er);
  }
}

/**
 * Forms {@link Polygon}s out of a graph of {@link DirectedEdge}s.
 * The edges to use are marked as being in the result Area.
 * <p>
 *
 * @version 1.7
 */
class PolygonBuilder {
  GeometryFactory geometryFactory;
  List shellList = [];

  PolygonBuilder(GeometryFactory geometryFactory) {
    this.geometryFactory = geometryFactory;
  }

  /**
   * Add a complete graph.
   * The graph is assumed to contain one or more polygons,
   * possibly with holes.
   */
  void addGraph(PlanarGraph graph) {
    add(graph.getEdgeEnds(), graph.getNodes());
  }

  /**
   * Add a set of edges and nodes, which form a graph.
   * The graph is assumed to contain one or more polygons,
   * possibly with holes.
   */
  void add(List dirEdges, List nodes) {
    PlanarGraph.linkResultDirectedEdgesStatic(nodes);
    List maxEdgeRings = buildMaximalEdgeRings(dirEdges);
    List freeHoleList = [];
    List edgeRings =
        buildMinimalEdgeRings(maxEdgeRings, shellList, freeHoleList);
    sortShellsAndHoles(edgeRings, shellList, freeHoleList);
    placeFreeHoles(shellList, freeHoleList);
    //Assert: every hole on freeHoleList has a shell assigned to it
  }

  List<Polygon> getPolygons() {
    List<Polygon> resultPolyList = computePolygons(shellList);
    return resultPolyList;
  }

  /**
   * for all DirectedEdges in result, form them into MaximalEdgeRings
   */
  List buildMaximalEdgeRings(List dirEdges) {
    List maxEdgeRings = [];
    for (DirectedEdge de in dirEdges) {
      if (de.isInResult() && de.getLabel().isArea()) {
        // if this edge has not yet been processed
        if (de.getEdgeRing() == null) {
          MaximalEdgeRing er = new MaximalEdgeRing(de, geometryFactory);
          maxEdgeRings.add(er);
          er.setInResult();
//System.out.println("max node degree = " + er.getMaxDegree());
        }
      }
    }
    return maxEdgeRings;
  }

  List buildMinimalEdgeRings(
      List maxEdgeRings, List shellList, List freeHoleList) {
    List edgeRings = [];
    for (MaximalEdgeRing er in maxEdgeRings) {
      if (er.getMaxNodeDegree() > 2) {
        er.linkDirectedEdgesForMinimalEdgeRings();
        List minEdgeRings = er.buildMinimalRings();
        // at this point we can go ahead and attempt to place holes, if this EdgeRing is a polygon
        EdgeRing shell = findShell(minEdgeRings);
        if (shell != null) {
          placePolygonHoles(shell, minEdgeRings);
          shellList.add(shell);
        } else {
          freeHoleList.addAll(minEdgeRings);
        }
      } else {
        edgeRings.add(er);
      }
    }
    return edgeRings;
  }

  /**
   * This method takes a list of MinimalEdgeRings derived from a MaximalEdgeRing,
   * and tests whether they form a Polygon.  This is the case if there is a single shell
   * in the list.  In this case the shell is returned.
   * The other possibility is that they are a series of connected holes, in which case
   * no shell is returned.
   *
   * @return the shell EdgeRing, if there is one
   * or null, if all the rings are holes
   */
  EdgeRing findShell(List minEdgeRings) {
    int shellCount = 0;
    EdgeRing shell;
    for (EdgeRing er in minEdgeRings) {
      if (!er.isHole()) {
        shell = er;
        shellCount++;
      }
    }
    Assert.isTrue(shellCount <= 1, "found two shells in MinimalEdgeRing list");
    return shell;
  }

  /**
   * This method assigns the holes for a Polygon (formed from a list of
   * MinimalEdgeRings) to its shell.
   * Determining the holes for a MinimalEdgeRing polygon serves two purposes:
   * <ul>
   * <li>it is faster than using a point-in-polygon check later on.
   * <li>it ensures correctness, since if the PIP test was used the point
   * chosen might lie on the shell, which might return an incorrect result from the
   * PIP test
   * </ul>
   */
  void placePolygonHoles(EdgeRing shell, List minEdgeRings) {
    for (MinimalEdgeRing er in minEdgeRings) {
      if (er.isHole()) {
        er.setShell(shell);
      }
    }
  }

  /**
   * For all rings in the input list,
   * determine whether the ring is a shell or a hole
   * and add it to the appropriate list.
   * Due to the way the DirectedEdges were linked,
   * a ring is a shell if it is oriented CW, a hole otherwise.
   */
  void sortShellsAndHoles(List edgeRings, List shellList, List freeHoleList) {
    for (EdgeRing er in edgeRings) {
//      er.setInResult();
      if (er.isHole()) {
        freeHoleList.add(er);
      } else {
        shellList.add(er);
      }
    }
  }

  /**
   * This method determines finds a containing shell for all holes
   * which have not yet been assigned to a shell.
   * These "free" holes should
   * all be <b>properly</b> contained in their parent shells, so it is safe to use the
   * <code>findEdgeRingContaining</code> method.
   * (This is the case because any holes which are NOT
   * properly contained (i.e. are connected to their
   * parent shell) would have formed part of a MaximalEdgeRing
   * and been handled in a previous step).
   *
   * @throws TopologyException if a hole cannot be assigned to a shell
   */
  void placeFreeHoles(List shellList, List freeHoleList) {
    for (EdgeRing hole in freeHoleList) {
      // only place this hole if it doesn't yet have a shell
      if (hole.getShell() == null) {
        EdgeRing shell = findEdgeRingContaining(hole, shellList);
        if (shell == null)
          throw new TopologyException.withCoord(
              "unable to assign hole to a shell", hole.getCoordinate(0));
//        Assert.isTrue(shell != null, "unable to assign hole to a shell");
        hole.setShell(shell);
      }
    }
  }

  /**
   * Find the innermost enclosing shell EdgeRing containing the argument EdgeRing, if any.
   * The innermost enclosing ring is the <i>smallest</i> enclosing ring.
   * The algorithm used depends on the fact that:
   * <br>
   *  ring A contains ring B iff envelope(ring A) contains envelope(ring B)
   * <br>
   * This routine is only safe to use if the chosen point of the hole
   * is known to be properly contained in a shell
   * (which is guaranteed to be the case if the hole does not touch its shell)
   *
   * @return containing EdgeRing, if there is one
   * or null if no containing EdgeRing is found
   */
  static EdgeRing findEdgeRingContaining(EdgeRing testEr, List shellList) {
    LinearRing testRing = testEr.getLinearRing();
    Envelope testEnv = testRing.getEnvelopeInternal();
    Coordinate testPt = testRing.getCoordinateN(0);

    EdgeRing minShell = null;
    Envelope minShellEnv = null;
    for (EdgeRing tryShell in shellList) {
      LinearRing tryShellRing = tryShell.getLinearRing();
      Envelope tryShellEnv = tryShellRing.getEnvelopeInternal();
      // the hole envelope cannot equal the shell envelope
      // (also guards against testing rings against themselves)
      if (tryShellEnv == testEnv) continue;
      // hole must be contained in shell
      if (!tryShellEnv.containsEnvelope(testEnv)) continue;

      testPt = CoordinateArrays.ptNotInList(
          testRing.getCoordinates(), tryShellRing.getCoordinates());
      bool isContained = false;
      if (PointLocation.isInRing(testPt, tryShellRing.getCoordinates()))
        isContained = true;

      // check if this new containing ring is smaller than the current minimum ring
      if (isContained) {
        if (minShell == null || minShellEnv.containsEnvelope(tryShellEnv)) {
          minShell = tryShell;
          minShellEnv = minShell.getLinearRing().getEnvelopeInternal();
        }
      }
    }
    return minShell;
  }

  List<Polygon> computePolygons(List shellList) {
    List<Polygon> resultPolyList = [];
    // add Polygons for all shells
    for (EdgeRing er in shellList) {
      Polygon poly = er.toPolygon(geometryFactory);
      resultPolyList.add(poly);
    }
    return resultPolyList;
  }
}

class LineBuilder {
  OverlayOp op;
  GeometryFactory geometryFactory;
  PointLocator ptLocator;
  List lineEdgesList = [];
  List<LineString> resultLineList = [];

  LineBuilder(
      OverlayOp op, GeometryFactory geometryFactory, PointLocator ptLocator) {
    this.op = op;
    this.geometryFactory = geometryFactory;
    this.ptLocator = ptLocator;
  }

  List build(int opCode) {
    findCoveredLineEdges();
    collectLines(opCode);
    buildLines(opCode);
    return resultLineList;
  }

  void findCoveredLineEdges() {
    for (Iterator nodeit = op.getGraph().getNodes().iterator;
        nodeit.moveNext();) {
      Node node = nodeit.current;
      (node.getEdges() as DirectedEdgeStar).findCoveredLineEdges();
    }
    for (Iterator it = op.getGraph().getEdgeEnds().iterator; it.moveNext();) {
      DirectedEdge de = it.current;
      Edge e = de.getEdge();
      if (de.isLineEdge() && (!e.isCoveredSet())) {
        bool isCovered = op.isCoveredByA(de.getCoordinate());
        e.setCovered(isCovered);
      }
    }
  }

  void collectLines(int opCode) {
    for (Iterator it = op.getGraph().getEdgeEnds().iterator; it.moveNext();) {
      DirectedEdge de = it.current;
      collectLineEdge(de, opCode, lineEdgesList);
      collectBoundaryTouchEdge(de, opCode, lineEdgesList);
    }
  }

  void collectLineEdge(DirectedEdge de, int opCode, List edges) {
    Label label = de.getLabel();
    Edge e = de.getEdge();
    if (de.isLineEdge()) {
      if (((!de.isVisited()) && OverlayOp.isResultOfOp(label, opCode)) &&
          (!e.isCovered())) {
        edges.add(e);
        de.setVisitedEdge(true);
      }
    }
  }

  void collectBoundaryTouchEdge(DirectedEdge de, int opCode, List edges) {
    Label label = de.getLabel();
    if (de.isLineEdge()) {
      return;
    }
    if (de.isVisited()) {
      return;
    }
    if (de.isInteriorAreaEdge()) {
      return;
    }
    if (de.getEdge().isInResult()) {
      return;
    }
    Assert.isTrue((!(de.isInResult() || de.getSym().isInResult())) ||
        (!de.getEdge().isInResult()));
    if (OverlayOp.isResultOfOp(label, opCode) &&
        (opCode == OverlayOp.INTERSECTION)) {
      edges.add(de.getEdge());
      de.setVisitedEdge(true);
    }
  }

  void buildLines(int opCode) {
    for (Iterator it = lineEdgesList.iterator; it.moveNext();) {
      Edge e = it.current;
      LineString line = geometryFactory.createLineString(e.getCoordinates());
      resultLineList.add(line);
      e.setInResult(true);
    }
  }

  void labelIsolatedLines(List edgesList) {
    for (Iterator it = edgesList.iterator; it.moveNext();) {
      Edge e = it.current;
      Label label = e.getLabel();
      if (e.isIsolated()) {
        if (label.isNull(0)) {
          labelIsolatedLine(e, 0);
        } else {
          labelIsolatedLine(e, 1);
        }
      }
    }
  }

  void labelIsolatedLine(Edge e, int targetIndex) {
    int loc =
        ptLocator.locate(e.getCoordinate(), op.getArgGeometry(targetIndex));
    e.getLabel().setLocationWithIndex(targetIndex, loc);
  }
}

/**
 * Computes the geometric overlay of two {@link Geometry}s.  The overlay
 * can be used to determine any boolean combination of the geometries.
 *
 * @version 1.7
 */
class OverlayOp extends GeometryGraphOperation {
  /**
   * The spatial functions supported by this class.
   * These operations implement various boolean combinations of the resultants of the overlay.
   */

  /**
   * The code for the Intersection overlay operation.
   */
  static const int INTERSECTION = 1;

  /**
   * The code for the Union overlay operation.
   */
  static const int UNION = 2;

  /**
   *  The code for the Difference overlay operation.
   */
  static const int DIFFERENCE = 3;

  /**
   *  The code for the Symmetric Difference overlay operation.
   */
  static const int SYMDIFFERENCE = 4;

  /**
   * Computes an overlay operation for
   * the given geometry arguments.
   *
   * @param geom0 the first geometry argument
   * @param geom1 the second geometry argument
   * @param opCode the code for the desired overlay operation
   * @return the result of the overlay operation
   * @throws TopologyException if a robustness problem is encountered
   */
  static Geometry overlayOp(Geometry geom0, Geometry geom1, int opCode) {
    OverlayOp gov = new OverlayOp(geom0, geom1);
    Geometry geomOv = gov.getResultGeometry(opCode);
    return geomOv;
  }

  /**
   * Tests whether a point with a given topological {@link Label}
   * relative to two geometries is contained in
   * the result of overlaying the geometries using
   * a given overlay operation.
   * <p>
   * The method handles arguments of {@link Location#NONE} correctly
   *
   * @param label the topological label of the point
   * @param opCode the code for the overlay operation to test
   * @return true if the label locations correspond to the overlayOpCode
   */
  static bool isResultOfOp(Label label, int opCode) {
    int loc0 = label.getLocation(0);
    int loc1 = label.getLocation(1);
    return isResultOfOp3(loc0, loc1, opCode);
  }

  /**
   * Tests whether a point with given {@link Location}s
   * relative to two geometries is contained in
   * the result of overlaying the geometries using
   * a given overlay operation.
   * <p>
   * The method handles arguments of {@link Location#NONE} correctly
   *
   * @param loc0 the code for the location in the first geometry
   * @param loc1 the code for the location in the second geometry
   * @param overlayOpCode the code for the overlay operation to test
   * @return true if the locations correspond to the overlayOpCode
   */
  static bool isResultOfOp3(int loc0, int loc1, int overlayOpCode) {
    if (loc0 == Location.BOUNDARY) loc0 = Location.INTERIOR;
    if (loc1 == Location.BOUNDARY) loc1 = Location.INTERIOR;
    switch (overlayOpCode) {
      case INTERSECTION:
        return loc0 == Location.INTERIOR && loc1 == Location.INTERIOR;
      case UNION:
        return loc0 == Location.INTERIOR || loc1 == Location.INTERIOR;
      case DIFFERENCE:
        return loc0 == Location.INTERIOR && loc1 != Location.INTERIOR;
      case SYMDIFFERENCE:
        return (loc0 == Location.INTERIOR && loc1 != Location.INTERIOR) ||
            (loc0 != Location.INTERIOR && loc1 == Location.INTERIOR);
    }
    return false;
  }

  final PointLocator _ptLocator = new PointLocator();
  GeometryFactory _geomFact;
  Geometry _resultGeom;

  PlanarGraph _graph;
  EdgeList _edgeList = new EdgeList();

  List<Geometry> _resultPolyList = [];
  List<Geometry> _resultLineList = [];
  List<Geometry> _resultPointList = [];

  /**
   * Constructs an instance to compute a single overlay operation
   * for the given geometries.
   *
   * @param g0 the first geometry argument
   * @param g1 the second geometry argument
   */
  OverlayOp(Geometry g0, Geometry g1) : super(g0, g1) {
    _graph = PlanarGraph.withFactory(OverlayNodeFactory());
    /**
     * Use factory of primary geometry.
     * Note that this does NOT handle mixed-precision arguments
     * where the second arg has greater precision than the first.
     */
    _geomFact = g0.getFactory();
  }

  /**
   * Gets the result of the overlay for a given overlay operation.
   * <p>
   * Note: this method can be called once only.
   *
   * @param overlayOpCode the overlay operation to perform
   * @return the compute result geometry
   * @throws TopologyException if a robustness problem is encountered
   */
  Geometry getResultGeometry(int overlayOpCode) {
    _computeOverlay(overlayOpCode);
    return _resultGeom;
  }

  /**
   * Gets the graph constructed to compute the overlay.
   *
   * @return the overlay graph
   */
  PlanarGraph getGraph() {
    return _graph;
  }

  void _computeOverlay(int opCode) {
    // copy points from input Geometries.
    // This ensures that any Point geometries
    // in the input are considered for inclusion in the result set
    _copyPoints(0);
    _copyPoints(1);

    // node the input Geometries
    arg[0].computeSelfNodes(li, false);
    arg[1].computeSelfNodes(li, false);

    // compute intersections between edges of the two input geometries
    arg[0].computeEdgeIntersections(arg[1], li, true);

    List baseSplitEdges = [];
    arg[0].computeSplitEdges(baseSplitEdges);
    arg[1].computeSplitEdges(baseSplitEdges);
    List splitEdges = baseSplitEdges;
    // add the noded edges to this result graph
    _insertUniqueEdges(baseSplitEdges);

    _computeLabelsFromDepths();
    _replaceCollapsedEdges();

//Debug.println(edgeList);

    /**
     * Check that the noding completed correctly.
     *
     * This test is slow, but necessary in order to catch robustness failure
     * situations.
     * If an exception is thrown because of a noding failure,
     * then snapping will be performed, which will hopefully avoid the problem.
     * In the future hopefully a faster check can be developed.
     *
     */
    EdgeNodingValidator.checkValidStatic(_edgeList.getEdges());

    _graph.addEdges(_edgeList.getEdges());
    _computeLabelling();
//Debug.printWatch();
    _labelIncompleteNodes();
//Debug.printWatch();
//nodeMap.print(System.out);

    /**
     * The ordering of building the result Geometries is important.
     * Areas must be built before lines, which must be built before points.
     * This is so that lines which are covered by areas are not included
     * explicitly, and similarly for points.
     */
    _findResultAreaEdges(opCode);
    _cancelDuplicateResultEdges();

    PolygonBuilder polyBuilder = new PolygonBuilder(_geomFact);
    polyBuilder.addGraph(_graph);
    _resultPolyList = polyBuilder.getPolygons();

    LineBuilder lineBuilder = new LineBuilder(this, _geomFact, _ptLocator);
    _resultLineList = lineBuilder.build(opCode);

    PointBuilder pointBuilder = new PointBuilder(this, _geomFact, _ptLocator);
    _resultPointList = pointBuilder.build(opCode);

    // gather the results from all calculations into a single Geometry for the result set
    _resultGeom = _computeGeometry(
      _resultPointList,
      _resultLineList,
      _resultPolyList,
      opCode,
    );
  }

  void _insertUniqueEdges(List edges) {
    for (Iterator i = edges.iterator; i.moveNext();) {
      Edge e = i.current as Edge;
      insertUniqueEdge(e);
    }
  }

  /**
   * Insert an edge from one of the noded input graphs.
   * Checks edges that are inserted to see if an
   * identical edge already exists.
   * If so, the edge is not inserted, but its label is merged
   * with the existing edge.
   */
  void insertUniqueEdge(Edge e) {
//<FIX> MD 8 Oct 03  speed up identical edge lookup
    // fast lookup
    Edge existingEdge = _edgeList.findEqualEdge(e);

    // If an identical edge already exists, simply update its label
    if (existingEdge != null) {
      Label existingLabel = existingEdge.getLabel();

      Label labelToMerge = e.getLabel();
      // check if new edge is in reverse direction to existing edge
      // if so, must flip the label before merging it
      if (!existingEdge.isPointwiseEqual(e)) {
        labelToMerge = Label.fromLabel(e.getLabel());
        labelToMerge.flip();
      }
      Depth depth = existingEdge.getDepth();
      // if this is the first duplicate found for this edge, initialize the depths
      ///*
      if (depth.isNull()) {
        depth.add(existingLabel);
      }
      //*/
      depth.add(labelToMerge);
      existingLabel.merge(labelToMerge);
//Debug.print("inserted edge: "); Debug.println(e);
//Debug.print("existing edge: "); Debug.println(existingEdge);

    } else {
      // no matching existing edge was found
      // add this new edge to the list of edges in this graph
      //e.setName(name + edges.size());
      //e.getDepth().add(e.getLabel());
      _edgeList.add(e);
    }
  }

  /**
   * If either of the GeometryLocations for the existing label is
   * exactly opposite to the one in the labelToMerge,
   * this indicates a dimensional collapse has happened.
   * In this case, convert the label for that Geometry to a Line label
   */
  /* NOT NEEDED?
  private void checkDimensionalCollapse(Label labelToMerge, Label existingLabel)
  {
    if (existingLabel.isArea() && labelToMerge.isArea()) {
      for (int i = 0; i < 2; i++) {
        if (! labelToMerge.isNull(i)
            &&  labelToMerge.getLocation(i, Position.LEFT)  == existingLabel.getLocation(i, Position.RIGHT)
            &&  labelToMerge.getLocation(i, Position.RIGHT) == existingLabel.getLocation(i, Position.LEFT) )
        {
          existingLabel.toLine(i);
        }
      }
    }
  }
  */
  /**
   * Update the labels for edges according to their depths.
   * For each edge, the depths are first normalized.
   * Then, if the depths for the edge are equal,
   * this edge must have collapsed into a line edge.
   * If the depths are not equal, update the label
   * with the locations corresponding to the depths
   * (i.e. a depth of 0 corresponds to a Location of EXTERIOR,
   * a depth of 1 corresponds to INTERIOR)
   */
  void _computeLabelsFromDepths() {
    for (Iterator it = _edgeList.iterator(); it.moveNext();) {
      Edge e = it.current as Edge;
      Label lbl = e.getLabel();
      Depth depth = e.getDepth();
      /**
       * Only check edges for which there were duplicates,
       * since these are the only ones which might
       * be the result of dimensional collapses.
       */
      if (!depth.isNull()) {
        depth.normalize();
        for (int i = 0; i < 2; i++) {
          if (!lbl.isNull(i) && lbl.isArea() && !depth.isNull1(i)) {
            /**
             * if the depths are equal, this edge is the result of
             * the dimensional collapse of two or more edges.
             * It has the same location on both sides of the edge,
             * so it has collapsed to a line.
             */
            if (depth.getDelta(i) == 0) {
              lbl.toLine(i);
            } else {
              /**
               * This edge may be the result of a dimensional collapse,
               * but it still has different locations on both sides.  The
               * label of the edge must be updated to reflect the resultant
               * side locations indicated by the depth values.
               */
              Assert.isTrue(!depth.isNull2(i, Position.LEFT),
                  "depth of LEFT side has not been initialized");
              lbl.setLocation(
                  i, Position.LEFT, depth.getLocation(i, Position.LEFT));
              Assert.isTrue(!depth.isNull2(i, Position.RIGHT),
                  "depth of RIGHT side has not been initialized");
              lbl.setLocation(
                  i, Position.RIGHT, depth.getLocation(i, Position.RIGHT));
            }
          }
        }
      }
    }
  }

  /**
   * If edges which have undergone dimensional collapse are found,
   * replace them with a new edge which is a L edge
   */
  void _replaceCollapsedEdges() {
    List<Edge> newEdges = [];
    List<Edge> removeEdges = [];

    for(final e in _edgeList.edges) {
      if (e.isCollapsed()) {
        removeEdges.add(e);
        newEdges.add(e.getCollapsedEdge());
      }
    }

    for (final re in removeEdges)
      _edgeList.edges.remove(re);

    _edgeList.addAll(newEdges);
  }

  /**
   * Copy all nodes from an arg geometry into this graph.
   * The node label in the arg geometry overrides any previously computed
   * label for that argIndex.
   * (E.g. a node may be an intersection node with
   * a previously computed label of BOUNDARY,
   * but in the original arg Geometry it is actually
   * in the interior due to the Boundary Determination Rule)
   */
  void _copyPoints(int argIndex) {
    for (Iterator i = arg[argIndex].getNodeIterator(); i.moveNext();) {
      Node graphNode = i.current as Node;
      Node newNode = _graph.addNodeFromCoordinate(graphNode.getCoordinate());
      newNode.setLabelWithIndex(
          argIndex, graphNode.getLabel().getLocation(argIndex));
    }
  }

  /**
   * Compute initial labelling for all DirectedEdges at each node.
   * In this step, DirectedEdges will acquire a complete labelling
   * (i.e. one with labels for both Geometries)
   * only if they
   * are incident on a node which has edges for both Geometries
   */
  void _computeLabelling() {
    for (Iterator nodeit = _graph.getNodes().iterator; nodeit.moveNext();) {
      Node node = nodeit.current as Node;
//if (node.getCoordinate().equals(new Coordinate(222, 100)) ) Debug.addWatch(node.getEdges());
      node.getEdges().computeLabelling(arg);
    }
    _mergeSymLabels();
    _updateNodeLabelling();
  }

  /**
   * For nodes which have edges from only one Geometry incident on them,
   * the previous step will have left their dirEdges with no labelling for the other
   * Geometry.  However, the sym dirEdge may have a labelling for the other
   * Geometry, so merge the two labels.
   */
  void _mergeSymLabels() {
    for (Iterator nodeit = _graph.getNodes().iterator; nodeit.moveNext();) {
      Node node = nodeit.current;
      (node.getEdges() as DirectedEdgeStar).mergeSymLabels();
      //node.print(System.out);
    }
  }

  void _updateNodeLabelling() {
    // update the labels for nodes
    // The label for a node is updated from the edges incident on it
    // (Note that a node may have already been labelled
    // because it is a point in one of the input geometries)
    for (Iterator nodeit = _graph.getNodes().iterator; nodeit.moveNext();) {
      Node node = nodeit.current as Node;
      Label lbl = (node.getEdges() as DirectedEdgeStar).getLabel();
      node.getLabel().merge(lbl);
    }
  }

  /**
   * Incomplete nodes are nodes whose labels are incomplete.
   * (e.g. the location for one Geometry is null).
   * These are either isolated nodes,
   * or nodes which have edges from only a single Geometry incident on them.
   *
   * Isolated nodes are found because nodes in one graph which don't intersect
   * nodes in the other are not completely labelled by the initial process
   * of adding nodes to the nodeList.
   * To complete the labelling we need to check for nodes that lie in the
   * interior of edges, and in the interior of areas.
   * <p>
   * When each node labelling is completed, the labelling of the incident
   * edges is updated, to complete their labelling as well.
   */
  void _labelIncompleteNodes() {
    // int nodeCount = 0;
    for (Iterator ni = _graph.getNodes().iterator; ni.moveNext();) {
      Node n = ni.current as Node;
      Label label = n.getLabel();
      if (n.isIsolated()) {
        // nodeCount++;
        if (label.isNull(0))
          _labelIncompleteNode(n, 0);
        else
          _labelIncompleteNode(n, 1);
      }
      // now update the labelling for the DirectedEdges incident on this node
      (n.getEdges() as DirectedEdgeStar).updateLabelling(label);
//n.print(System.out);
    }
    /*
    int nPoly0 = arg[0].getGeometry().getNumGeometries();
    int nPoly1 = arg[1].getGeometry().getNumGeometries();
    System.out.println("# isolated nodes= " + nodeCount
    		+ "   # poly[0] = " + nPoly0
    		+ "   # poly[1] = " + nPoly1);
    */
  }

  /**
   * Label an isolated node with its relationship to the target geometry.
   */
  void _labelIncompleteNode(Node n, int targetIndex) {
    int loc =
        _ptLocator.locate(n.getCoordinate(), arg[targetIndex].getGeometry());

    // MD - 2008-10-24 - experimental for now
//    int loc = arg[targetIndex].locate(n.getCoordinate());
    n.getLabel().setLocationWithIndex(targetIndex, loc);
  }

  /**
   * Find all edges whose label indicates that they are in the result area(s),
   * according to the operation being performed.  Since we want polygon shells to be
   * oriented CW, choose dirEdges with the interior of the result on the RHS.
   * Mark them as being in the result.
   * Interior Area edges are the result of dimensional collapses.
   * They do not form part of the result area boundary.
   */
  void _findResultAreaEdges(int opCode) {
    for (Iterator it = _graph.getEdgeEnds().iterator; it.moveNext();) {
      DirectedEdge de = it.current;
      // mark all dirEdges with the appropriate label
      Label label = de.getLabel();
      if (label.isArea() &&
          !de.isInteriorAreaEdge() &&
          isResultOfOp3(label.getLocationWithPosIndex(0, Position.RIGHT),
              label.getLocationWithPosIndex(1, Position.RIGHT), opCode)) {
        de.setInResult(true);
//Debug.print("in result "); Debug.println(de);
      }
    }
  }

  /**
   * If both a dirEdge and its sym are marked as being in the result, cancel
   * them out.
   */
  void _cancelDuplicateResultEdges() {
    // remove any dirEdges whose sym is also included
    // (they "cancel each other out")
    for (Iterator it = _graph.getEdgeEnds().iterator; it.moveNext();) {
      DirectedEdge de = it.current;
      DirectedEdge sym = de.getSym();
      if (de.isInResult() && sym.isInResult()) {
        de.setInResult(false);
        sym.setInResult(false);
//Debug.print("cancelled "); Debug.println(de); Debug.println(sym);
      }
    }
  }

  /**
   * Tests if a point node should be included in the result or not.
   *
   * @param coord the point coordinate
   * @return true if the coordinate point is covered by a result Line or Area geometry
   */
  bool isCoveredByLA(Coordinate coord) {
    if (_isCovered(coord, _resultLineList)) return true;
    if (_isCovered(coord, _resultPolyList)) return true;
    return false;
  }

  /**
   * Tests if an L edge should be included in the result or not.
   *
   * @param coord the point coordinate
   * @return true if the coordinate point is covered by a result Area geometry
   */
  bool isCoveredByA(Coordinate coord) {
    if (_isCovered(coord, _resultPolyList)) return true;
    return false;
  }

  /**
   * @return true if the coord is located in the interior or boundary of
   * a geometry in the list.
   */
  bool _isCovered(Coordinate coord, List geomList) {
    for (Iterator it = geomList.iterator; it.moveNext();) {
      Geometry geom = it.current;
      int loc = _ptLocator.locate(coord, geom);
      if (loc != Location.EXTERIOR) return true;
    }
    return false;
  }

  Geometry _computeGeometry(
    List<Geometry> resultPointList,
    List<Geometry> resultLineList,
    List<Geometry> resultPolyList,
    int opcode,
  ) {
    List<Geometry> geomList = [];
    // element geometries of the result are always in the order P,L,A
    geomList.addAll(resultPointList);
    geomList.addAll(resultLineList);
    geomList.addAll(resultPolyList);

    //*
    if (geomList.isEmpty)
      return createEmptyResult(
          opcode, arg[0].getGeometry(), arg[1].getGeometry(), _geomFact);
    //*/

    // build the most specific geometry possible
    return _geomFact.buildGeometry(geomList);
  }

  /**
   * Creates an empty result geometry of the appropriate dimension,
   * based on the given overlay operation and the dimensions of the inputs.
   * The created geometry is always an atomic geometry,
   * not a collection.
   * <p>
   * The empty result is constructed using the following rules:
   * <ul>
   * <li>{@link #INTERSECTION} - result has the dimension of the lowest input dimension
   * <li>{@link #UNION} - result has the dimension of the highest input dimension
   * <li>{@link #DIFFERENCE} - result has the dimension of the left-hand input
   * <li>{@link #SYMDIFFERENCE} - result has the dimension of the highest input dimension
   * (since the symmetric Difference is the union of the differences).
   * </ul>
   *
   * @param overlayOpCode the code for the overlay operation being performed
   * @param a an input geometry
   * @param b an input geometry
   * @param geomFact the geometry factory being used for the operation
   * @return an empty atomic geometry of the appropriate dimension
   */
  static Geometry createEmptyResult(
      int overlayOpCode, Geometry a, Geometry b, GeometryFactory geomFact) {
    Geometry result = null;
    int resultDim = _resultDimension(overlayOpCode, a, b);

    /**
     * Handles resultSDim = -1, although should not happen
     */
    return result = geomFact.createEmpty(resultDim);
  }

  static int _resultDimension(int opCode, Geometry g0, Geometry g1) {
    int dim0 = g0.getDimension();
    int dim1 = g1.getDimension();

    int resultDimension = -1;
    switch (opCode) {
      case OverlayOp.INTERSECTION:
        resultDimension = math.min(dim0, dim1);
        break;
      case OverlayOp.UNION:
        resultDimension = math.max(dim0, dim1);
        break;
      case OverlayOp.DIFFERENCE:
        resultDimension = dim0;
        break;
      case OverlayOp.SYMDIFFERENCE:
        /**
       * This result is chosen because
       * <pre>
       * SymDiff = Union(Diff(A, B), Diff(B, A)
       * </pre>
       * and Union has the dimension of the highest-dimension argument.
       */
        resultDimension = math.max(dim0, dim1);
        break;
    }
    return resultDimension;
  }
}

class PointBuilder {
  OverlayOp op;
  GeometryFactory geometryFactory;
  List<Point> resultPointList = [];

  PointBuilder(
      OverlayOp op, GeometryFactory geometryFactory, PointLocator ptLocator) {
    this.op = op;
    this.geometryFactory = geometryFactory;
  }

  List<Point> build(int opCode) {
    extractNonCoveredResultNodes(opCode);
    return resultPointList;
  }

  void extractNonCoveredResultNodes(int opCode) {
    for (Iterator nodeit = op.getGraph().getNodes().iterator;
        nodeit.moveNext();) {
      Node n = nodeit.current;
      if (n.isInResult()) {
        continue;
      }
      if (n.isIncidentEdgeInResult()) {
        continue;
      }
      if ((n.getEdges().getDegree() == 0) ||
          (opCode == OverlayOp.INTERSECTION)) {
        Label label = n.getLabel();
        if (OverlayOp.isResultOfOp(label, opCode)) {
          filterCoveredNodeToPoint(n);
        }
      }
    }
  }

  void filterCoveredNodeToPoint(Node n) {
    Coordinate coord = n.getCoordinate();
    if (!op.isCoveredByLA(coord)) {
      Point pt = geometryFactory.createPoint(coord);
      resultPointList.add(pt);
    }
  }
}

class SnapIfNeededOverlayOp {
  static Geometry overlayOp(Geometry g0, Geometry g1, int opCode) {
    SnapIfNeededOverlayOp op = SnapIfNeededOverlayOp(g0, g1);
    return op.getResultGeometry(opCode);
  }

  static Geometry intersection(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.INTERSECTION);
  }

  static Geometry union(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.UNION);
  }

  static Geometry difference(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.DIFFERENCE);
  }

  static Geometry symDifference(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.SYMDIFFERENCE);
  }

  List<Geometry> geom = new List<Geometry>(2);

  SnapIfNeededOverlayOp(Geometry g1, Geometry g2) {
    geom[0] = g1;
    geom[1] = g2;
  }

  Geometry getResultGeometry(int opCode) {
    Geometry result = null;
    bool isSuccess = false;
    RuntimeException savedException = null;
    try {
      result = OverlayOp.overlayOp(geom[0], geom[1], opCode);
      bool isValid = true;
      if (isValid) {
        isSuccess = true;
      }
    } on RuntimeException catch (ex) {
      savedException = ex;
    }
    if (!isSuccess) {
      try {
        result = SnapOverlayOp.overlayOp(geom[0], geom[1], opCode);
      } on RuntimeException catch (ex) {
        throw savedException;
      }
    }
    return result;
  }
}

class SnapOverlayOp {
  static Geometry overlayOp(Geometry g0, Geometry g1, int opCode) {
    SnapOverlayOp op = new SnapOverlayOp(g0, g1);
    return op.getResultGeometry(opCode);
  }

  static Geometry intersection(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.INTERSECTION);
  }

  static Geometry union(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.UNION);
  }

  static Geometry difference(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.DIFFERENCE);
  }

  static Geometry symDifference(Geometry g0, Geometry g1) {
    return overlayOp(g0, g1, OverlayOp.SYMDIFFERENCE);
  }

  List<Geometry> geom = new List<Geometry>(2);
  double snapTolerance;

  SnapOverlayOp(Geometry g1, Geometry g2) {
    geom[0] = g1;
    geom[1] = g2;
    computeSnapTolerance();
  }

  void computeSnapTolerance() {
    snapTolerance =
        GeometrySnapper.computeOverlaySnapTolerance2(geom[0], geom[1]);
  }

  Geometry getResultGeometry(int opCode) {
    List<Geometry> prepGeom = snap(geom);
    Geometry result = OverlayOp.overlayOp(prepGeom[0], prepGeom[1], opCode);
    return prepareResult(result);
  }

  Geometry selfSnap(Geometry geom) {
    GeometrySnapper snapper0 = new GeometrySnapper(geom);
    Geometry snapGeom = snapper0.snapTo(geom, snapTolerance);
    return snapGeom;
  }

  List<Geometry> snap(List<Geometry> geom) {
    List<Geometry> remGeom = removeCommonBits(geom);
    List<Geometry> snapGeom =
        GeometrySnapper.snap(remGeom[0], remGeom[1], snapTolerance);
    return snapGeom;
  }

  Geometry prepareResult(Geometry geom) {
    cbr.addCommonBits(geom);
    return geom;
  }

  CommonBitsRemover cbr;

  List<Geometry> removeCommonBits(List<Geometry> geom) {
    cbr = new CommonBitsRemover();
    cbr.add(geom[0]);
    cbr.add(geom[1]);
    List<Geometry> remGeom = new List<Geometry>(2);
    remGeom[0] = cbr.removeCommonBits(geom[0].copy());
    remGeom[1] = cbr.removeCommonBits(geom[1].copy());
    return remGeom;
  }

  void checkValid(Geometry g) {
    if (!g.isValid()) {
      print("Snapped geometry is invalid");
    }
  }
}

class GeometrySnapper {
  static const double SNAP_PRECISION_FACTOR = 1e-9;

  /**
   * Estimates the snap tolerance for a Geometry, taking into account its precision model.
   *
   * @param g a Geometry
   * @return the estimated snap tolerance
   */
  static double computeOverlaySnapTolerance(Geometry g) {
    double snapTolerance = computeSizeBasedSnapTolerance(g);

    /**
     * Overlay is carried out in the precision model
     * of the two inputs.
     * If this precision model is of type FIXED, then the snap tolerance
     * must reflect the precision grid size.
     * Specifically, the snap tolerance should be at least
     * the distance from a corner of a precision grid cell
     * to the centre point of the cell.
     */
    PrecisionModel pm = g.getPrecisionModel();
    if (pm.getType() == PrecisionModel.FIXED) {
      double fixedSnapTol = (1 / pm.getScale()) * 2 / 1.415;
      if (fixedSnapTol > snapTolerance) snapTolerance = fixedSnapTol;
    }
    return snapTolerance;
  }

  static double computeSizeBasedSnapTolerance(Geometry g) {
    Envelope env = g.getEnvelopeInternal();
    double minDimension = math.min(env.getHeight(), env.getWidth());
    double snapTol = minDimension * SNAP_PRECISION_FACTOR;
    return snapTol;
  }

  static double computeOverlaySnapTolerance2(Geometry g0, Geometry g1) {
    return math.min(
        computeOverlaySnapTolerance(g0), computeOverlaySnapTolerance(g1));
  }

  /**
   * Snaps two geometries together with a given tolerance.
   *
   * @param g0 a geometry to snap
   * @param g1 a geometry to snap
   * @param snapTolerance the tolerance to use
   * @return the snapped geometries
   */
  static List<Geometry> snap(Geometry g0, Geometry g1, double snapTolerance) {
    List<Geometry> snapGeom = [];
    GeometrySnapper snapper0 = new GeometrySnapper(g0);
    snapGeom[0] = snapper0.snapTo(g1, snapTolerance);

    /**
     * Snap the second geometry to the snapped first geometry
     * (this strategy minimizes the number of possible different points in the result)
     */
    GeometrySnapper snapper1 = new GeometrySnapper(g1);
    snapGeom[1] = snapper1.snapTo(snapGeom[0], snapTolerance);

//    System.out.println(snap[0]);
//    System.out.println(snap[1]);
    return snapGeom;
  }

  /**
   * Snaps a geometry to itself.
   * Allows optionally cleaning the result to ensure it is
   * topologically valid
   * (which fixes issues such as topology collapses in polygonal inputs).
   * <p>
   * Snapping a geometry to itself can remove artifacts such as very narrow slivers, gores and spikes.
   *
   *@param geom the geometry to snap
   *@param snapTolerance the snapping tolerance
   *@param cleanResult whether the result should be made valid
   * @return a new snapped Geometry
   */
  static Geometry snapToSelfStatic(
      Geometry geom, double snapTolerance, bool cleanResult) {
    GeometrySnapper snapper0 = new GeometrySnapper(geom);
    return snapper0.snapToSelf(snapTolerance, cleanResult);
  }

  Geometry srcGeom;

  /**
   * Creates a new snapper acting on the given geometry
   *
   * @param srcGeom the geometry to snap
   */
  GeometrySnapper(Geometry srcGeom) {
    this.srcGeom = srcGeom;
  }

  /**
   * Snaps the vertices in the component {@link LineString}s
   * of the source geometry
   * to the vertices of the given snap geometry.
   *
   * @param snapGeom a geometry to snap the source to
   * @return a new snapped Geometry
   */
  Geometry snapTo(Geometry snapGeom, double snapTolerance) {
    List<Coordinate> snapPts = extractTargetCoordinates(snapGeom);

    SnapTransformer snapTrans = new SnapTransformer(snapTolerance, snapPts);
    return snapTrans.transform(srcGeom);
  }

  /**
   * Snaps the vertices in the component {@link LineString}s
   * of the source geometry
   * to the vertices of the same geometry.
   * Allows optionally cleaning the result to ensure it is
   * topologically valid
   * (which fixes issues such as topology collapses in polygonal inputs).
   *
   *@param snapTolerance the snapping tolerance
   *@param cleanResult whether the result should be made valid
   * @return a new snapped Geometry
   */
  Geometry snapToSelf(double snapTolerance, bool cleanResult) {
    List<Coordinate> snapPts = extractTargetCoordinates(srcGeom);

    SnapTransformer snapTrans =
        new SnapTransformer(snapTolerance, snapPts, isSelfSnap: true);
    Geometry snappedGeom = snapTrans.transform(srcGeom);
    Geometry result = snappedGeom;
    if (cleanResult && result is Polygonal) {
      // TODO: use better cleaning approach
      result = snappedGeom.buffer(0);
    }
    return result;
  }

  List<Coordinate> extractTargetCoordinates(Geometry g) {
    // TODO: should do this more efficiently.  Use CoordSeq filter to get points, KDTree for uniqueness & queries
    Set ptSet = HashSet<Coordinate>();
    List<Coordinate> pts = g.getCoordinates();
    for (int i = 0; i < pts.length; i++) {
      ptSet.add(pts[i]);
    }
    return ptSet.toList();
  }

  /**
   * Computes the snap tolerance based on the input geometries.
   *
   * @param ringPts
   * @return
   */
  double computeSnapTolerance(List<Coordinate> ringPts) {
    double minSegLen = computeMinimumSegmentLength(ringPts);
    // use a small percentage of this to be safe
    double snapTol = minSegLen / 10;
    return snapTol;
  }

  double computeMinimumSegmentLength(List<Coordinate> pts) {
    double minSegLen = double.maxFinite;
    for (int i = 0; i < pts.length - 1; i++) {
      double segLen = pts[i].distance(pts[i + 1]);
      if (segLen < minSegLen) minSegLen = segLen;
    }
    return minSegLen;
  }
}

class SnapTransformer extends GeometryTransformer {
  double snapTolerance;
  List<Coordinate> snapPts;
  bool isSelfSnap = false;

  SnapTransformer(double snapTolerance, List<Coordinate> snapPts,
      {bool isSelfSnap = false}) {
    this.snapTolerance = snapTolerance;
    this.snapPts = snapPts;
    this.isSelfSnap = isSelfSnap;
  }

  CoordinateSequence transformCoordinates(
      CoordinateSequence coords, Geometry parent) {
    List<Coordinate> srcPts = coords.toCoordinateArray();
    List<Coordinate> newPts = snapLine(srcPts, snapPts);
    return factory.getCoordinateSequenceFactory().create(newPts);
  }

  List<Coordinate> snapLine(List<Coordinate> srcPts, List<Coordinate> snapPts) {
    LineStringSnapper snapper = new LineStringSnapper(srcPts, snapTolerance);
    snapper.setAllowSnappingToSourceVertices(isSelfSnap);
    return snapper.snapTo(snapPts);
  }
}

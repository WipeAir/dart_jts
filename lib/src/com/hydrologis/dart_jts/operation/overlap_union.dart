part of dart_jts;

class OverlapUnion
{
  static Geometry unionStatic(Geometry g0, Geometry g1)
  {
    OverlapUnion union = new OverlapUnion(g0, g1);
    return union.union();
  }

  GeometryFactory geomFactory;
  Geometry g0;
  Geometry g1;
  bool isUnionSafe;


  /**
   * Creates a new instance for unioning the given geometries.
   *
   * @param g0 a geometry to union
   * @param g1 a geometry to union
   */
  OverlapUnion(Geometry g0, Geometry g1)
  {
    this.g0 = g0;
    this.g1 = g1;
    geomFactory = g0.getFactory();
  }

  /**
   * Unions the input geometries,
   * using the more performant overlap union algorithm if possible.
   *
   * @return the union of the inputs
   */
  Geometry union()
  {
    Envelope overlapEnv = overlapEnvelope(g0,  g1);

    /**
     * If no overlap, can just combine the geometries
     */
    if (overlapEnv.isNull()) {
      Geometry g0Copy = g0.copy();
      Geometry g1Copy = g1.copy();
      return GeometryCombiner.combine2(g0Copy, g1Copy);
    }

    List<Geometry> disjointPolys = [];

    Geometry g0Overlap = extractByEnvelope(overlapEnv, g0, disjointPolys);
    Geometry g1Overlap = extractByEnvelope(overlapEnv, g1, disjointPolys);

//    System.out.println("# geoms in common: " + intersectingPolys.size());
    Geometry unionGeom = unionFull(g0Overlap, g1Overlap);

    Geometry result = null;
    isUnionSafe = isBorderSegmentsSame(unionGeom, overlapEnv);
    if (! isUnionSafe) {
      // overlap union changed border segments... need to do full union
      //System.out.println("OverlapUnion: Falling back to full union");
      result = unionFull(g0, g1);
    }
    else {
      //System.out.println("OverlapUnion: fast path");
      result = combine(unionGeom, disjointPolys);
    }
    return result;
  }

  /**
   * Allows checking whether the optimized
   * or full union was performed.
   * Used for unit testing.
   *
   * @return true if the optimized union was performed
   */
  bool isUnionOptimized() {
    return isUnionSafe;
  }

  static Envelope overlapEnvelope(Geometry g0, Geometry g1) {
    Envelope g0Env = g0.getEnvelopeInternal();
    Envelope g1Env = g1.getEnvelopeInternal();
    Envelope overlapEnv = g0Env.intersection(g1Env);
    return overlapEnv;
  }

  Geometry combine(Geometry unionGeom, List<Geometry> disjointPolys) {
    if (disjointPolys.length <= 0)
      return unionGeom;

    disjointPolys.add(unionGeom);
    Geometry result = GeometryCombiner.combine1(disjointPolys);
    return result;
  }

  Geometry extractByEnvelope(Envelope env, Geometry geom,
      List<Geometry> disjointGeoms)
  {
    List<Geometry> intersectingGeoms = [];
    for (int i = 0; i < geom.getNumGeometries(); i++) {
      Geometry elem = geom.getGeometryN(i);
      if (elem.getEnvelopeInternal().intersectsEnvelope(env)) {
        intersectingGeoms.add(elem);
      }
      else {
        Geometry copy = elem.copy();
        disjointGeoms.add(copy);
      }
    }
    return geomFactory.buildGeometry(intersectingGeoms);
  }

  Geometry unionFull(Geometry geom0, Geometry geom1) {
    try {
      return geom0.unionOther(geom1);
    } on TopologyException {
      /**
       * If the overlay union fails,
       * try a buffer union, which often succeeds
       */
      return unionBuffer(geom0, geom1);
    }
  }

  /**
   * Implements union using the buffer-by-zero trick.
   * This seems to be more robust than overlay union,
   * for reasons somewhat unknown.
   *
   * @param g0 a geometry
   * @param g1 a geometry
   * @return the union of the geometries
   */
  static Geometry unionBuffer(Geometry g0, Geometry g1)
  {
    GeometryFactory factory = g0.getFactory();
    Geometry gColl = factory.createGeometryCollection([g0, g1]);
    Geometry union = gColl.buffer(0.0);
    return union;
  }

  bool isBorderSegmentsSame(Geometry result, Envelope env) {
    List<LineSegment> segsBefore = extractBorderSegments(g0, g1, env);

    List<LineSegment> segsAfter = [];
    extractBorderSegmentsStatic(result, env, segsAfter);

    //System.out.println("# seg before: " + segsBefore.size() + " - # seg after: " + segsAfter.size());
    return isEqual(segsBefore, segsAfter);
  }

  bool isEqual(List<LineSegment> segs0, List<LineSegment> segs1) {
    if (segs0.length != segs1.length)
      return false;

    Set<LineSegment> segIndex = new HashSet<LineSegment>();
    segIndex.addAll(segs0);

    for (final seg in segs1) {
      if (! segIndex.contains(seg)) {
        //System.out.println("Found changed border seg: " + seg);
        return false;
      }
    }
    return true;
  }

  List<LineSegment> extractBorderSegments(Geometry geom0, Geometry geom1, Envelope env) {
    List<LineSegment> segs = [];
    extractBorderSegmentsStatic(geom0, env, segs);
    if (geom1 != null)
      extractBorderSegmentsStatic(geom1, env, segs);
    return segs;
  }

  static bool intersects(Envelope env, Coordinate p0, Coordinate p1) {
    return env.intersectsCoordinate(p0) || env.intersectsCoordinate(p1);
  }

  static bool containsProperly3(Envelope env, Coordinate p0, Coordinate p1) {
    return containsProperly2(env, p0) && containsProperly2(env, p1);
  }

  static bool containsProperly2(Envelope env, Coordinate p) {
    if (env.isNull()) return false;
    return p.getX() > env.getMinX() &&
        p.getX() < env.getMaxX() &&
        p.getY() > env.getMinY() &&
        p.getY() < env.getMaxY();
  }

  static void extractBorderSegmentsStatic(Geometry geom, Envelope env, List<LineSegment> segs) {
    geom.applyCSF(_ExtractBorderSegmentsStaticApply(env, segs));
  }
}

class _ExtractBorderSegmentsStaticApply implements CoordinateSequenceFilter {
  final Envelope env;
  final List<LineSegment> segs;

  _ExtractBorderSegmentsStaticApply(this.env, this.segs);

  void filter(CoordinateSequence seq, int i) {
    if (i <= 0) return;

    // extract LineSegment
    Coordinate p0 = seq.getCoordinate(i - 1);
    Coordinate p1 = seq.getCoordinate(i);
    bool isBorder = OverlapUnion.intersects(env, p0, p1) && ! OverlapUnion.containsProperly3(env, p0, p1);
    if (isBorder) {
      LineSegment seg = LineSegment.fromCoordinates(p0, p1);
      segs.add(seg);
    }
  }

  bool isDone() {   return false;   }

  bool isGeometryChanged() {   return false;   }
}

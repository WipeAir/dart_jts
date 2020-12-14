part of dart_jts;

class GeometryTransformer {
  /**
   * Possible extensions:
   * getParent() method to return immediate parent e.g. of LinearRings in Polygons
   */

  Geometry inputGeom;

  GeometryFactory factory = null;

  // these could eventually be exposed to clients
  /**
   * <code>true</code> if empty geometries should not be included in the result
   */
  bool pruneEmptyGeometry = true;

  /**
   * <code>true</code> if a homogenous collection result
   * from a {@link GeometryCollection} should still
   * be a general GeometryCollection
   */
  bool preserveGeometryCollectionType = true;

  /**
   * <code>true</code> if the output from a collection argument should still be a collection
   */
  bool preserveCollections = false;

  /**
   * <code>true</code> if the type of the input should be preserved
   */
  bool preserveType = false;

  /**
   * Utility function to make input geometry available
   *
   * @return the input geometry
   */
  Geometry getInputGeometry() {
    return inputGeom;
  }

  Geometry transform(Geometry inputGeom) {
    this.inputGeom = inputGeom;
    this.factory = inputGeom.getFactory();

    if (inputGeom is Point) return transformPoint(inputGeom, null);
    if (inputGeom is MultiPoint) return transformMultiPoint(inputGeom, null);
    if (inputGeom is LinearRing) return transformLinearRing(inputGeom, null);
    if (inputGeom is LineString) return transformLineString(inputGeom, null);
    if (inputGeom is MultiLineString)
      return transformMultiLineString(inputGeom, null);
    if (inputGeom is Polygon) return transformPolygon(inputGeom, null);
    if (inputGeom is MultiPolygon)
      return transformMultiPolygon(inputGeom, null);
    if (inputGeom is GeometryCollection)
      return transformGeometryCollection(inputGeom, null);

    // throw new IllegalArgumentError("Unknown Geometry subtype: " + inputGeom.getClass().getName());
  }

  /**
   * Convenience method which provides standard way of
   * creating a {@link CoordinateSequence}
   *
   * @param coords the coordinate array to copy
   * @return a coordinate sequence for the array
   */
  CoordinateSequence createCoordinateSequence(List<Coordinate> coords) {
    return factory.getCoordinateSequenceFactory().create(coords);
  }

  /**
   * Convenience method which provides a standard way of copying {@link CoordinateSequence}s
   * @param seq the sequence to copy
   * @return a deep copy of the sequence
   */
  CoordinateSequence copy(CoordinateSequence seq) {
    return seq.copy();
  }

  /**
   * Transforms a {@link CoordinateSequence}.
   * This method should always return a valid coordinate list for
   * the desired result type.  (E.g. a coordinate list for a LineString
   * must have 0 or at least 2 points).
   * If this is not possible, return an empty sequence -
   * this will be pruned out.
   *
   * @param coords the coordinates to transform
   * @param parent the parent geometry
   * @return the transformed coordinates
   */
  CoordinateSequence transformCoordinates(
      CoordinateSequence coords, Geometry parent) {
    return copy(coords);
  }

  Geometry transformPoint(Point geom, Geometry parent) {
    return factory.createPointSeq(
        transformCoordinates(geom.getCoordinateSequence(), geom));
  }

  Geometry transformMultiPoint(MultiPoint geom, Geometry parent) {
    List<Geometry> transGeomList = [];
    for (int i = 0; i < geom.getNumGeometries(); i++) {
      Geometry transformGeom =
          transformPoint(geom.getGeometryN(i) as Point, geom);
      if (transformGeom == null) continue;
      if (transformGeom.isEmpty()) continue;
      transGeomList.add(transformGeom);
    }
    return factory.buildGeometry(transGeomList);
  }

  /**
   * Transforms a LinearRing.
   * The transformation of a LinearRing may result in a coordinate sequence
   * which does not form a structurally valid ring (i.e. a degenerate ring of 3 or fewer points).
   * In this case a LineString is returned.
   * Subclasses may wish to override this method and check for this situation
   * (e.g. a subclass may choose to eliminate degenerate linear rings)
   *
   * @param geom the ring to simplify
   * @param parent the parent geometry
   * @return a LinearRing if the transformation resulted in a structurally valid ring
   * @return a LineString if the transformation caused the LinearRing to collapse to 3 or fewer points
   */
  Geometry transformLinearRing(LinearRing geom, Geometry parent) {
    CoordinateSequence seq =
        transformCoordinates(geom.getCoordinateSequence(), geom);
    if (seq == null) return factory.createLinearRingSeq(null);
    int seqSize = seq.size();
    // ensure a valid LinearRing
    if (seqSize > 0 && seqSize < 4 && !preserveType)
      return factory.createLineStringSeq(seq);
    return factory.createLinearRingSeq(seq);
  }

  /**
   * Transforms a {@link LineString} geometry.
   *
   * @param geom
   * @param parent
   * @return
   */
  Geometry transformLineString(LineString geom, Geometry parent) {
    // should check for 1-point sequences and downgrade them to points
    return factory.createLineStringSeq(
        transformCoordinates(geom.getCoordinateSequence(), geom));
  }

  Geometry transformMultiLineString(MultiLineString geom, Geometry parent) {
    List<Geometry> transGeomList = [];
    for (int i = 0; i < geom.getNumGeometries(); i++) {
      Geometry transformGeom =
          transformLineString(geom.getGeometryN(i) as LineString, geom);
      if (transformGeom == null) continue;
      if (transformGeom.isEmpty()) continue;
      transGeomList.add(transformGeom);
    }
    return factory.buildGeometry(transGeomList);
  }

  Geometry transformPolygon(Polygon geom, Geometry parent) {
    bool isAllValidLinearRings = true;
    Geometry shell = transformLinearRing(geom.getExteriorRing(), geom);

    if (shell == null || !(shell is LinearRing) || shell.isEmpty())
      isAllValidLinearRings = false;

    List<LinearRing> holes = [];
    for (int i = 0; i < geom.getNumInteriorRing(); i++) {
      Geometry hole = transformLinearRing(geom.getInteriorRingN(i), geom);
      if (hole == null || hole.isEmpty()) {
        continue;
      }
      if (!(hole is LinearRing)) isAllValidLinearRings = false;

      holes.add(hole);
    }

    if (isAllValidLinearRings)
      return factory.createPolygon(shell as LinearRing, holes);
    else {
      List<Geometry> components = [];
      if (shell != null) components.add(shell);
      components.addAll(holes);
      return factory.buildGeometry(components);
    }
  }

  Geometry transformMultiPolygon(MultiPolygon geom, Geometry parent) {
    List<Geometry> transGeomList = [];
    for (int i = 0; i < geom.getNumGeometries(); i++) {
      Geometry transformGeom =
          transformPolygon(geom.getGeometryN(i) as Polygon, geom);
      if (transformGeom == null) continue;
      if (transformGeom.isEmpty()) continue;
      transGeomList.add(transformGeom);
    }
    return factory.buildGeometry(transGeomList);
  }

  Geometry transformGeometryCollection(
      GeometryCollection geom, Geometry parent) {
    List<Geometry> transGeomList = [];
    for (int i = 0; i < geom.getNumGeometries(); i++) {
      Geometry transformGeom = transform(geom.getGeometryN(i));
      if (transformGeom == null) continue;
      if (pruneEmptyGeometry && transformGeom.isEmpty()) continue;
      transGeomList.add(transformGeom);
    }
    if (preserveGeometryCollectionType)
      return factory.createGeometryCollection(transGeomList);
    return factory.buildGeometry(transGeomList);
  }
}

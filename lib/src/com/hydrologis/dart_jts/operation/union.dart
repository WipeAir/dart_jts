part of dart_jts;

/**
 * Extracts atomic elements from
 * input geometries or collections,
 * recording the dimension found.
 * Empty geometries are discarded since they
 * do not contribute to the result of {@link UnaryUnionOp}.
 *
 * @author Martin Davis
 *
 */
class InputExtracter implements GeometryFilter {
  /**
   * Extracts elements from a collection of geometries.
   *
   * @param geoms a collection of geometries
   * @return an extracter over the geometries
   */
  static InputExtracter extractMulti(List<Geometry> geoms) {
    InputExtracter extracter = new InputExtracter();
    extracter._addMulti(geoms);
    return extracter;
  }

  /**
   * Extracts elements from a geometry.
   *
   * @param geoms a geometry to extract from
   * @return an extracter over the geometry
   */
  static InputExtracter extractSingle(Geometry geom) {
    InputExtracter extracter = new InputExtracter();
    extracter._addSingle(geom);
    return extracter;
  }

  GeometryFactory geomFactory = null;
  final polygons = <Polygon>[];
  final lines = <LineString>[];
  final points = <Point>[];

  /**
   * The default dimension for an empty GeometryCollection
   */
  int _dimension = Dimension.FALSE;

  /**
   * Tests whether there were any non-empty geometries extracted.
   *
   * @return true if there is a non-empty geometry present
   */
  bool isEmpty() {
    return polygons.isEmpty && lines.isEmpty && points.isEmpty;
  }

  /**
   * Gets the maximum dimension extracted.
   *
   * @return the maximum extracted dimension
   */
  int getDimension() {
    return _dimension;
  }

  /**
   * Gets the geometry factory from the extracted geometry,
   * if there is one.
   * If an empty collection was extracted, will return <code>null</code>.
   *
   * @return a geometry factory, or null if one could not be determined
   */
  GeometryFactory getFactory() {
    return geomFactory;
  }

  /**
   * Gets the extracted atomic geometries of the given dimension <code>dim</code>.
   *
   * @param dim the dimension of geometry to return
   * @return a list of the extracted geometries of dimension dim.
   */
  List<Geometry> getExtract(int dim) {
    switch (dim) {
      case 0:
        return points;
      case 1:
        return lines;
      case 2:
        return polygons;
    }
    Assert.shouldNeverReachHere("Invalid dimension: $dim");
    return null;
  }

  void _addMulti(List<Geometry> geoms) {
    for (final geom in geoms) {
      _addSingle(geom);
    }
  }

  void _addSingle(Geometry geom) {
    if (geomFactory == null) geomFactory = geom.getFactory();

    geom.applyGF(this);
  }

  @override
  void filter(Geometry geom) {
    _recordDimension(geom.getDimension());

    if (geom is GeometryCollection) {
      return;
    }
    /**
     * Don't keep empty geometries
     */
    if (geom.isEmpty()) return;

    if (geom is Polygon) {
      polygons.add(geom);
      return;
    } else if (geom is LineString) {
      lines.add(geom);
      return;
    } else if (geom is Point) {
      points.add(geom);
      return;
    }
    Assert.shouldNeverReachHere(
        "Unhandled geometry type: " + geom.getGeometryType());
  }

  void _recordDimension(int dim) {
    if (dim > _dimension) _dimension = dim;
  }
}

/**
 * Unions a <code>Collection</code> of {@link Geometry}s or a single Geometry
 * (which may be a {@link GeoometryCollection}) together.
 * By using this special-purpose operation over a collection of geometries
 * it is possible to take advantage of various optimizations to improve performance.
 * Heterogeneous {@link GeometryCollection}s are fully supported.
 * <p>
 * The result obeys the following contract:
 * <ul>
 * <li>Unioning a set of {@link Polygon}s has the effect of
 * merging the areas (i.e. the same effect as
 * iteratively unioning all individual polygons together).
 *
 * <li>Unioning a set of {@link LineString}s has the effect of <b>noding</b>
 * and <b>dissolving</b> the input linework.
 * In this context "fully noded" means that there will be
 * an endpoint or node in the result
 * for every endpoint or line segment crossing in the input.
 * "Dissolved" means that any duplicate (i.e. coincident) line segments or portions
 * of line segments will be reduced to a single line segment in the result.
 * This is consistent with the semantics of the
 * {@link Geometry#union(Geometry)} operation.
 * If <b>merged</b> linework is required, the {@link LineMerger} class can be used.
 *
 * <li>Unioning a set of {@link Point}s has the effect of merging
 * all identical points (producing a set with no duplicates).
 * </ul>
 *
 * <tt>UnaryUnion</tt> always operates on the individual components of MultiGeometries.
 * So it is possible to use it to "clean" invalid self-intersecting MultiPolygons
 * (although the polygon components must all still be individually valid.)
 *
 * @author mbdavis
 *
 */
class UnaryUnionOp {
  /**
   * Computes the geometric union of a {@link Collection}
   * of {@link Geometry}s.
   *
   * @param geoms a collection of geometries
   * @return the union of the geometries,
   * or <code>null</code> if the input is empty
   */
  static Geometry unionMulti(List<Geometry> geoms) {
    UnaryUnionOp op = new UnaryUnionOp(geoms, null);
    return op.union();
  }

  /**
   * Computes the geometric union of a {@link Collection}
   * of {@link Geometry}s.
   *
   * If no input geometries were provided but a {@link GeometryFactory} was provided,
   * an empty {@link GeometryCollection} is returned.
   *
   * @param geoms a collection of geometries
   * @param geomFact the geometry factory to use if the collection is empty
   * @return the union of the geometries,
   * or an empty GEOMETRYCOLLECTION
   */
  static Geometry unionMultiWithFactory(
      List<Geometry> geoms, GeometryFactory geomFact) {
    UnaryUnionOp op = new UnaryUnionOp(geoms, geomFact);
    return op.union();
  }

  /**
   * Constructs a unary union operation for a {@link Geometry}
   * (which may be a {@link GeometryCollection}).
   *
   * @param geom a geometry to union
   * @return the union of the elements of the geometry
   * or an empty GEOMETRYCOLLECTION
   */
  static Geometry unionSingle(Geometry geom) {
    UnaryUnionOp op = new UnaryUnionOp([geom], null);
    return op.union();
  }

  GeometryFactory _geomFact;
  InputExtracter _extracter;

  /**
   * Constructs a unary union operation for a {@link Collection}
   * of {@link Geometry}s.
   *
   * @param geoms a collection of geometries
   * @param geomFact the geometry factory to use if the collection is empty
   */
  UnaryUnionOp(List<Geometry> geoms, GeometryFactory geomFact) {
    _geomFact = geomFact;
    _extractMulti(geoms);
  }

  void _extractMulti(List<Geometry> geoms) {
    _extracter = InputExtracter.extractMulti(geoms);
  }

  void _extractSingle(Geometry geom) {
    _extracter = InputExtracter.extractSingle(geom);
  }

  /**
   * Gets the union of the input geometries.
   * <p>
   * The result of empty input is determined as follows:
   * <ol>
   * <li>If the input is empty and a dimension can be
   * determined (i.e. an empty geometry is present),
   * an empty atomic geometry of that dimension is returned.
   * <li>If no input geometries were provided but a {@link GeometryFactory} was provided,
   * an empty {@link GeometryCollection} is returned.
   * <li>Otherwise, the return value is <code>null</code>.
   * </ol>
   *
   * @return a Geometry containing the union,
   * or an empty atomic geometry, or an empty GEOMETRYCOLLECTION,
   * or <code>null</code> if no GeometryFactory was provided
   */
  Geometry union() {
    if (_geomFact == null) _geomFact = _extracter.getFactory();

    // Case 3
    if (_geomFact == null) {
      return null;
    }

    // Case 1 & 2
    if (_extracter.isEmpty()) {
      return _geomFact.createEmpty(_extracter.getDimension());
    }
    List points = _extracter.getExtract(0);
    List lines = _extracter.getExtract(1);
    List polygons = _extracter.getExtract(2);

    /**
     * For points and lines, only a single union operation is
     * required, since the OGC model allows self-intersecting
     * MultiPoint and MultiLineStrings.
     * This is not the case for polygons, so Cascaded Union is required.
     */
    Geometry unionPoints = null;
    if (points.length > 0) {
      Geometry ptGeom = _geomFact.buildGeometry(points);
      unionPoints = _unionNoOpt(ptGeom);
    }

    Geometry unionLines = null;
    if (lines.length > 0) {
      Geometry lineGeom = _geomFact.buildGeometry(lines);
      unionLines = _unionNoOpt(lineGeom);
    }

    Geometry unionPolygons = null;
    if (polygons.length > 0) {
      unionPolygons = CascadedPolygonUnion.unionStatic(polygons);
    }

    /**
     * Performing two unions is somewhat inefficient,
     * but is mitigated by unioning lines and points first
     */
    Geometry unionLA = _unionWithNull(unionLines, unionPolygons);
    Geometry union = null;
    if (unionPoints == null)
      union = unionLA;
    else if (unionLA == null)
      union = unionPoints;
    else
      union = PointGeometryUnion.unionStatic(unionPoints as Puntal, unionLA);

    if (union == null) return _geomFact.createGeometryCollection([]);

    return union;
  }

  /**
   * Computes the union of two geometries,
   * either of both of which may be null.
   *
   * @param g0 a Geometry
   * @param g1 a Geometry
   * @return the union of the input(s)
   * or null if both inputs are null
   */
  Geometry _unionWithNull(Geometry g0, Geometry g1) {
    if (g0 == null && g1 == null) return null;

    if (g1 == null) return g0;
    if (g0 == null) return g1;

    return g0.unionOther(g1);
  }

  /**
   * Computes a unary union with no extra optimization,
   * and no short-circuiting.
   * Due to the way the overlay operations
   * are implemented, this is still efficient in the case of linear
   * and puntal geometries.
   * Uses robust version of overlay operation
   * to ensure identical behaviour to the <tt>union(Geometry)</tt> operation.
   *
   * @param g0 a geometry
   * @return the union of the input geometry
   */
  Geometry _unionNoOpt(Geometry g0) {
    Geometry empty = _geomFact.createPointEmpty();
    return SnapIfNeededOverlayOp.overlayOp(g0, empty, OverlayOp.UNION);
  }
}

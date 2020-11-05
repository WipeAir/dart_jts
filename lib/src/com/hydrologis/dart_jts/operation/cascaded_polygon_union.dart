part of dart_jts;

/**
 * Provides an efficient method of unioning a collection of
 * {@link Polygonal} geometries.
 * The geometries are indexed using a spatial index,
 * and unioned recursively in index order.
 * For geometries with a high degree of overlap,
 * this has the effect of reducing the number of vertices
 * early in the process, which increases speed
 * and robustness.
 * <p>
 * This algorithm is faster and more robust than
 * the simple iterated approach of
 * repeatedly unioning each polygon to a result geometry.
 * <p>
 * The <tt>buffer(0)</tt> trick is sometimes faster, but can be less robust and
 * can sometimes take a long time to complete.
 * This is particularly the case where there is a high degree of overlap
 * between the polygons.  In this case, <tt>buffer(0)</tt> is forced to compute
 * with <i>all</i> line segments from the outset,
 * whereas cascading can eliminate many segments
 * at each stage of processing.
 * The best situation for using <tt>buffer(0)</tt> is the trivial case
 * where there is <i>no</i> overlap between the input geometries.
 * However, this case is likely rare in practice.
 *
 * @author Martin Davis
 *
 */
class CascadedPolygonUnion
{
  /**
   * Computes the union of
   * a collection of {@link Polygonal} {@link Geometry}s.
   *
   * @param polys a collection of {@link Polygonal} {@link Geometry}s
   */
  static Geometry unionStatic(List polys)
  {
    CascadedPolygonUnion op = new CascadedPolygonUnion(polys);
    return op.union();
  }

  List inputPolys;
  GeometryFactory geomFactory = null;

  /**
   * Creates a new instance to union
   * the given collection of {@link Geometry}s.
   *
   * @param polys a collection of {@link Polygonal} {@link Geometry}s
   */
  CascadedPolygonUnion(List polys)
  {
    this.inputPolys = polys;
    // guard against null input
    if (inputPolys == null)
      inputPolys = [];
  }

  /**
   * The effectiveness of the index is somewhat sensitive
   * to the node capacity.
   * Testing indicates that a smaller capacity is better.
   * For an STRtree, 4 is probably a good number (since
   * this produces 2x2 "squares").
   */
  static final int STRTREE_NODE_CAPACITY = 4;

  /**
   * Computes the union of the input geometries.
   * <p>
   * This method discards the input geometries as they are processed.
   * In many input cases this reduces the memory retained
   * as the operation proceeds.
   * Optimal memory usage is achieved
   * by disposing of the original input collection
   * before calling this method.
   *
   * @return the union of the input geometries
   * or null if no input geometries were provided
   * @throws IllegalStateException if this method is called more than once
   */
  Geometry union()
  {
    // if (inputPolys == null)
    //   throw new IllegalStateException("union() method cannot be called twice");
    if (inputPolys.isEmpty)
      return null;
    geomFactory = inputPolys.first.getFactory();

  /**
   * A spatial index to organize the collection
   * into groups of close geometries.
   * This makes unioning more efficient, since vertices are more likely
   * to be eliminated on each round.
   */
//    STRtree index = new STRtree();
  STRtree index = STRtree.withCapacity(STRTREE_NODE_CAPACITY);
  for (Iterator i = inputPolys.iterator; i.moveNext(); ) {
  Geometry item = i.current;
  index.insert(item.getEnvelopeInternal(), item);
  }
    // To avoiding holding memory remove references to the input geometries,
    inputPolys = null;

    List itemTree = index.itemsTree();
//    printItemEnvelopes(itemTree);
  Geometry unionAll = unionTree(itemTree);
    return unionAll;
  }

  Geometry unionTree(List geomTree)
  {
    /**
     * Recursively unions all subtrees in the list into single geometries.
     * The result is a list of Geometrys only
     */
    List geoms = reduceToGeometries(geomTree);
//    Geometry union = bufferUnion(geoms);
    Geometry union = binaryUnion(geoms);

    // print out union (allows visualizing hierarchy)
//    System.out.println(union);

    return union;
  }

  //========================================================
  /*
   * The following methods are for experimentation only
   */

  Geometry repeatedUnion(List geoms)
  {
    Geometry union = null;
    for (Iterator i = geoms.iterator; i.moveNext(); ) {
      Geometry g = i.current;
      if (union == null)
        union = g.copy();
      else
        union = union.unionOther(g);
    }
    return union;
  }

  Geometry bufferUnion(List geoms)
  {
    GeometryFactory factory = (geoms[0] as Geometry).getFactory();
  Geometry gColl = factory.buildGeometry(geoms);
  Geometry unionAll = gColl.buffer(0.0);
    return unionAll;
  }

  Geometry bufferUnion2(Geometry g0, Geometry g1)
  {
    GeometryFactory factory = g0.getFactory();
    Geometry gColl = factory.createGeometryCollection([g0, g1]);
    Geometry unionAll = gColl.buffer(0.0);
    return unionAll;
  }

  //=======================================

  /**
   * Unions a list of geometries
   * by treating the list as a flattened binary tree,
   * and performing a cascaded union on the tree.
   */
  Geometry binaryUnion(List geoms)
  {
    return binaryUnion3(geoms, 0, geoms.length);
  }

  /**
   * Unions a section of a list using a recursive binary union on each half
   * of the section.
   *
   * @param geoms the list of geometries containing the section to union
   * @param start the start index of the section
   * @param end the index after the end of the section
   * @return the union of the list section
   */
  Geometry binaryUnion3(List geoms, int start, int end)
  {
    if (end - start <= 1) {
      Geometry g0 = getGeometry(geoms, start);
      return unionSafe(g0, null);
    }
    else if (end - start == 2) {
      return unionSafe(getGeometry(geoms, start), getGeometry(geoms, start + 1));
    }
    else {
      // recurse on both halves of the list
      int mid = (end + start) ~/ 2;
      Geometry g0 = binaryUnion3(geoms, start, mid);
      Geometry g1 = binaryUnion3(geoms, mid, end);
      return unionSafe(g0, g1);
    }
  }

  /**
   * Gets the element at a given list index, or
   * null if the index is out of range.
   *
   * @param list
   * @param index
   * @return the geometry at the given index
   * or null if the index is out of range
   */
  static Geometry getGeometry(List list, int index)
  {
    if (index >= list.length) return null;
    return list[index] as Geometry;
  }

  /**
   * Reduces a tree of geometries to a list of geometries
   * by recursively unioning the subtrees in the list.
   *
   * @param geomTree a tree-structured list of geometries
   * @return a list of Geometrys
   */
  List reduceToGeometries(List geomTree)
  {
    List geoms = [];
    for (Iterator i = geomTree.iterator; i.moveNext(); ) {
      Object o = i.current;
      Geometry geom = null;
      if (o is List) {
        geom = unionTree(o);
      }
      else if (o is Geometry) {
        geom =  o;
      }
      geoms.add(geom);
    }
    return geoms;
  }

  /**
   * Computes the union of two geometries,
   * either or both of which may be null.
   *
   * @param g0 a Geometry
   * @param g1 a Geometry
   * @return the union of the input(s)
   * or null if both inputs are null
   */
  Geometry unionSafe(Geometry g0, Geometry g1)
  {
    if (g0 == null && g1 == null)
      return null;

    if (g0 == null)
      return g1.copy();
    if (g1 == null)
      return g0.copy();

    return unionActual( g0, g1 );
  }

  /**
   * Encapsulates the actual unioning of two polygonal geometries.
   *
   * @param g0
   * @param g1
   * @return
   */
  Geometry unionActual(Geometry g0, Geometry g1)
  {
    Geometry union = OverlapUnion.unionStatic(g0, g1);
    return restrictToPolygons( union );
  }

  /**
   * Computes a {@link Geometry} containing only {@link Polygonal} components.
   * Extracts the {@link Polygon}s from the input
   * and returns them as an appropriate {@link Polygonal} geometry.
   * <p>
   * If the input is already <tt>Polygonal</tt>, it is returned unchanged.
   * <p>
   * A particular use case is to filter out non-polygonal components
   * returned from an overlay operation.
   *
   * @param g the geometry to filter
   * @return a Polygonal geometry
   */
  static Geometry restrictToPolygons(Geometry g)
  {
    if (g is Polygonal) {
      return g;
    }
    List polygons = PolygonExtracter.getPolygons(g);
    if (polygons.length == 1)
      return polygons[0] as Polygon;
    return g.getFactory().createMultiPolygon(polygons);
  }
}

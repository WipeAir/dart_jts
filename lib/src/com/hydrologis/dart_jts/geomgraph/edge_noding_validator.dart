part of dart_jts;

/**
 * Validates that a collection of {@link Edge}s is correctly noded.
 * Throws an appropriate exception if an noding error is found.
 * Uses {@link FastNodingValidator} to perform the validation.
 *
 * @version 1.7
 *
 * @see FastNodingValidator
 */
class EdgeNodingValidator {
  /**
   * Checks whether the supplied {@link Edge}s
   * are correctly noded.
   * Throws a  {@link TopologyException} if they are not.
   *
   * @param edges a collection of Edges.
   * @throws TopologyException if the SegmentStrings are not correctly noded
   *
   */
  static void checkValidStatic(List<Edge> edges) {
    EdgeNodingValidator validator = new EdgeNodingValidator(edges);
    validator.checkValid();
  }

  static List toSegmentStrings(List edges) {
    // convert Edges to SegmentStrings
    List segStrings = [];
    for (Iterator i = edges.iterator; i.moveNext();) {
      Edge e = i.current as Edge;
      segStrings.add(new BasicSegmentString(e.getCoordinates(), e));
    }
    return segStrings;
  }

  FastNodingValidator _nv;

  /**
   * Creates a new validator for the given collection of {@link Edge}s.
   *
   * @param edges a collection of Edges.
   */
  EdgeNodingValidator(List edges) {
    _nv = new FastNodingValidator(toSegmentStrings(edges));
  }

  /**
   * Checks whether the supplied edges
   * are correctly noded.  Throws an exception if they are not.
   *
   * @throws TopologyException if the SegmentStrings are not correctly noded
   *
   */
  void checkValid() {
    _nv.checkValid();
  }
}

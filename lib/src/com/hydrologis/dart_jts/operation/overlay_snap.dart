part of dart_jts;

class LineStringSnapper {
  double snapTolerance = 0;
  List<Coordinate> srcPts;
  LineSegment seg = LineSegment.empty();
  bool allowSnappingToSourceVertices = false;
  bool isClosed = false;

  LineStringSnapper(List<Coordinate> srcPts, double snapTolerance) {
    this.srcPts = srcPts;
    isClosed = isClosedStatic(srcPts);
    this.snapTolerance = snapTolerance;
  }

  factory LineStringSnapper.fromLineString(
      LineString srcLine, double snapTolerance) {
    return LineStringSnapper(srcLine.getCoordinates(), snapTolerance);
  }

  void setAllowSnappingToSourceVertices(bool allowSnappingToSourceVertices) {
    this.allowSnappingToSourceVertices = allowSnappingToSourceVertices;
  }

  static bool isClosedStatic(List<Coordinate> pts) {
    if (pts.length <= 1) {
      return false;
    }
    return pts[0].equals2D(pts[pts.length - 1]);
  }

  List<Coordinate> snapTo(List<Coordinate> snapPts) {
    CoordinateList coordList = CoordinateList.fromList(srcPts);
    snapVertices(coordList, snapPts);
    snapSegments(coordList, snapPts);
    List<Coordinate> newPts = coordList.toCoordinateArray();
    return newPts;
  }

  void snapVertices(CoordinateList srcCoords, List<Coordinate> snapPts) {
    int end = (isClosed
        ? (srcCoords._backingList.length - 1)
        : srcCoords._backingList.length);
    for (int i = 0; i < end; i++) {
      Coordinate srcPt = srcCoords.getCoordinate(i);
      Coordinate snapVert = findSnapForVertex(srcPt, snapPts);
      if (snapVert != null) {
        srcCoords.toCoordinateArray()[i] = Coordinate.fromCoordinate(snapVert);
        if ((i == 0) && isClosed) {
          srcCoords.toCoordinateArray()[srcCoords._backingList.length - 1] =
              Coordinate.fromCoordinate(snapVert);
        }
      }
    }
  }

  Coordinate findSnapForVertex(Coordinate pt, List<Coordinate> snapPts) {
    for (int i = 0; i < snapPts.length; i++) {
      if (pt.equals2D(snapPts[i])) {
        return null;
      }
      if (pt.distance(snapPts[i]) < snapTolerance) {
        return snapPts[i];
      }
    }
    return null;
  }

  void snapSegments(CoordinateList srcCoords, List<Coordinate> snapPts) {
    if (snapPts.length == 0) {
      return;
    }
    int distinctPtCount = snapPts.length;
    if (snapPts[0].equals2D(snapPts[snapPts.length - 1])) {
      distinctPtCount = (snapPts.length - 1);
    }
    for (int i = 0; i < distinctPtCount; i++) {
      Coordinate snapPt = snapPts[i];
      int index = findSegmentIndexToSnap(snapPt, srcCoords);
      if (index >= 0) {
        srcCoords.add33(index + 1, Coordinate.fromCoordinate(snapPt), false);
      }
    }
  }

  int findSegmentIndexToSnap(Coordinate snapPt, CoordinateList srcCoords) {
    double minDist = double.maxFinite;
    int snapIndex = (-1);
    for (int i = 0; i < (srcCoords._backingList.length - 1); i++) {
      seg.p0 = srcCoords.getCoordinate(i);
      seg.p1 = srcCoords.getCoordinate(i + 1);
      if (seg.p0.equals2D(snapPt) || seg.p1.equals2D(snapPt)) {
        if (allowSnappingToSourceVertices) {
          continue;
        } else {
          return -1;
        }
      }
      double dist = seg.distanceCoord(snapPt);
      if ((dist < snapTolerance) && (dist < minDist)) {
        minDist = dist;
        snapIndex = i;
      }
    }
    return snapIndex;
  }
}

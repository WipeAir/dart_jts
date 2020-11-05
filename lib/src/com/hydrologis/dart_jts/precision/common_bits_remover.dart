part of dart_jts;

class CommonBitsRemover {
  Coordinate commonCoord;
  CommonCoordinateFilter ccFilter = new CommonCoordinateFilter();

  CommonBitsRemover() {}

  void add(Geometry geom) {
    geom.applyCF(ccFilter);
    commonCoord = ccFilter.getCommonCoordinate();
  }

  Coordinate getCommonCoordinate() {
    return commonCoord;
  }

  Geometry removeCommonBits(Geometry geom) {
    if ((commonCoord.x == 0) && (commonCoord.y == 0)) {
      return geom;
    }
    Coordinate invCoord = Coordinate.fromCoordinate(commonCoord);
    invCoord.x = (-invCoord.x);
    invCoord.y = (-invCoord.y);
    Translater trans = Translater(invCoord);
    geom.applyCSF(trans);
    geom.geometryChanged();
    return geom;
  }

  void addCommonBits(Geometry geom) {
    Translater trans = new Translater(commonCoord);
    geom.applyCSF(trans);
    geom.geometryChanged();
  }
}

class CommonCoordinateFilter with CoordinateFilter {
  CommonBits commonBitsX = new CommonBits();
  CommonBits commonBitsY = new CommonBits();

  void filter(Coordinate coord) {
    commonBitsX.add(coord.x);
    commonBitsY.add(coord.y);
  }

  Coordinate getCommonCoordinate() {
    return new Coordinate(commonBitsX.getCommon(), commonBitsY.getCommon());
  }
}

class Translater with CoordinateSequenceFilter {
  Coordinate trans = null;

  Translater(Coordinate trans) {
    this.trans = trans;
  }

  void filter(CoordinateSequence seq, int i) {
    double xp = (seq.getOrdinate(i, 0) + trans.x);
    double yp = (seq.getOrdinate(i, 1) + trans.y);
    seq.setOrdinate(i, 0, xp);
    seq.setOrdinate(i, 1, yp);
  }

  bool isDone() {
    return false;
  }

  bool isGeometryChanged() {
    return true;
  }
}

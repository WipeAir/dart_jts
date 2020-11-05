part of dart_jts;

class PointGeometryUnion
{

  static Geometry unionStatic(Puntal pointGeom, Geometry otherGeom)
  {
    PointGeometryUnion unioner = PointGeometryUnion(pointGeom, otherGeom);
    return unioner.union();
  }
  Geometry pointGeom;
  Geometry otherGeom;
  GeometryFactory geomFact;

  PointGeometryUnion(Puntal pointGeom, Geometry otherGeom)
  {
    this.pointGeom = pointGeom as Geometry;
    this.otherGeom = otherGeom;
    geomFact = otherGeom.getFactory();
  }

  Geometry union()
  {
    PointLocator locater = new PointLocator();
    List<Coordinate> exteriorCoords = [];
    for (int i = 0; i < pointGeom.getNumGeometries(); i++) {
      Point point = pointGeom.getGeometryN(i);
      Coordinate coord = point.getCoordinate();
      int loc = locater.locate(coord, otherGeom);
      if (loc == Location.EXTERIOR) {
        exteriorCoords.add(coord);
      }
    }
    if (exteriorCoords.length == 0) {
      return otherGeom;
    }
    Geometry ptComp = null;
    List<Coordinate> coords = exteriorCoords;
    if (coords.length == 1) {
      ptComp = geomFact.createPoint(coords[0]);
    } else {
      ptComp = geomFact.createMultiPointFromCoords(coords);
    }
    return GeometryCombiner.combine2(ptComp, otherGeom);
  }
}

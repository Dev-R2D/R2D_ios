#if canImport(UIKit) && canImport(iNaviMaps)
import Foundation
import iNaviMaps

public enum R2DCoordinateConverter {
    public struct ProjectedCoordinate: Equatable {
        public let x: Double
        public let y: Double
    }

    public struct ConversionSet {
        public let wgs84: INVLatLng
        public let katec: ProjectedCoordinate
        public let utmk: ProjectedCoordinate
        public let tm: ProjectedCoordinate
        public let grs80: ProjectedCoordinate
    }

    public static func convertFromWGS84(_ latLng: INVLatLng) -> ConversionSet {
        let katec = INVKatec(latLng: latLng)
        let utmk = INVUtmk(latLng: latLng)
        let tm = INVTm(latLng: latLng)
        let grs80 = INVGrs80(latLng: latLng)

        return ConversionSet(
            wgs84: latLng,
            katec: .init(x: katec.x, y: katec.y),
            utmk: .init(x: utmk.x, y: utmk.y),
            tm: .init(x: tm.x, y: tm.y),
            grs80: .init(x: grs80.x, y: grs80.y)
        )
    }

    public static func katecToWGS84(x: Double, y: Double) -> INVLatLng {
        INVKatec(x: x, y: y).toLatLng()
    }

    public static func utmkToWGS84(x: Double, y: Double) -> INVLatLng {
        INVUtmk(x: x, y: y).toLatLng()
    }

    public static func tmToWGS84(x: Double, y: Double) -> INVLatLng {
        INVTm(x: x, y: y).toLatLng()
    }

    public static func grs80ToWGS84(x: Double, y: Double) -> INVLatLng {
        INVGrs80(x: x, y: y).toLatLng()
    }
}
#endif

import Foundation
import CoreLocation

public struct GPXTrackPoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double?
    public let timestamp: Date?
    
    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
    
    public init(latitude: Double, longitude: Double, elevation: Double? = nil, timestamp: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timestamp = timestamp
    }
}

public struct GPXParseResult: Equatable, Sendable {
    public let title: String
    public let points: [Coordinate]
    public let elevations: [Double]
    public let totalDistance: Double // meters
    public let elevationGain: Double // meters
    
    public init(title: String, points: [Coordinate], elevations: [Double], totalDistance: Double, elevationGain: Double) {
        self.title = title
        self.points = points
        self.elevations = elevations
        self.totalDistance = totalDistance
        self.elevationGain = elevationGain
    }
}

public final class GPXFileService: NSObject, XMLParserDelegate, @unchecked Sendable {
    public override init() {
        super.init()
    }
    
    private var currentElement = ""
    private var trackTitle = "GPX Import Track"
    private var parsedPoints: [Coordinate] = []
    private var parsedElevations: [Double] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentText = ""
    
    public func parse(xmlData: Data) throws -> GPXParseResult {
        parsedPoints.removeAll()
        parsedElevations.removeAll()
        currentText = ""
        trackTitle = "GPX Import Track"
        
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "GPXFileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "GPX 파일 파싱 실패"])
        }
        
        var totalDist: Double = 0
        for i in 0..<(parsedPoints.count - 1) {
            totalDist += haversineDistance(parsedPoints[i], parsedPoints[i+1])
        }
        
        var eleGain: Double = 0
        for i in 0..<(parsedElevations.count - 1) {
            let diff = parsedElevations[i+1] - parsedElevations[i]
            if diff > 0 { eleGain += diff }
        }
        
        return GPXParseResult(
            title: trackTitle,
            points: parsedPoints,
            elevations: parsedElevations,
            totalDistance: totalDist,
            elevationGain: eleGain
        )
    }
    
    // MARK: - XMLParserDelegate Methods
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""
        
        if currentElement == "trkpt" || currentElement == "rtept" || currentElement == "wpt" {
            let latStr = attributeDict["lat"] ?? attributeDict["LAT"] ?? attributeDict["Lat"]
            let lonStr = attributeDict["lon"] ?? attributeDict["LON"] ?? attributeDict["Lon"]
            if let latStr, let lat = Double(latStr), let lonStr, let lon = Double(lonStr) {
                currentLat = lat
                currentLon = lon
            }
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.lowercased()
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if tag == "name" && !trimmed.isEmpty && trackTitle == "GPX Import Track" {
            trackTitle = trimmed
        } else if tag == "ele" {
            currentEle = Double(trimmed)
        } else if tag == "trkpt" || tag == "rtept" || tag == "wpt" {
            if let lat = currentLat, let lon = currentLon {
                let coord = Coordinate(latitude: lat, longitude: lon)
                parsedPoints.append(coord)
                parsedElevations.append(currentEle ?? 45.0)
            }
            currentLat = nil
            currentLon = nil
            currentEle = nil
        }
    }
    
    // MARK: - GPX Export Engine (gpxstudio compliant)
    public func exportGPX(title: String, polyline: [Coordinate], elevations: [Double]? = nil) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="R2D RidingAzua / GPXStudio Engine" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(title)</name>
            <desc>R2D 도로상태 노면판별 모델 가공 GPX 코스</desc>
            <time>\(ISO8601DateFormatter().string(from: Date()))</time>
          </metadata>
          <trk>
            <name>\(title)</name>
            <trkseg>
        """
        
        for (index, coord) in polyline.enumerated() {
            let ele = (elevations != nil && elevations!.indices.contains(index)) ? elevations![index] : 45.0
            xml += "\n      <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\"><ele>\(String(format: "%.1f", ele))</ele></trkpt>"
        }
        
        xml += """

            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }
    
    private func haversineDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let r = 6371000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(h))
    }
}

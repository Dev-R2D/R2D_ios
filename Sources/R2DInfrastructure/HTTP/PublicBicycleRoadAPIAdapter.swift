import Foundation
import R2DCore

public struct PublicBicycleRoadRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let roadName: String
    public let startAddress: String
    public let endAddress: String
    public let startCoordinate: Coordinate
    public let endCoordinate: Coordinate
    public let totalLengthKM: Double
    public let roadType: String
    public let widthMeters: Double
    
    public init(
        id: String = UUID().uuidString,
        roadName: String,
        startAddress: String,
        endAddress: String,
        startCoordinate: Coordinate,
        endCoordinate: Coordinate,
        totalLengthKM: Double,
        roadType: String = "자전거전용도로",
        widthMeters: Double = 2.5
    ) {
        self.id = id
        self.roadName = roadName
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.totalLengthKM = totalLengthKM
        self.roadType = roadType
        self.widthMeters = widthMeters
    }
    
    public func generatePolyline() -> [Coordinate] {
        let steps = 25
        return (0...steps).map { i in
            let r = Double(i) / Double(steps)
            let lat = startCoordinate.latitude + (endCoordinate.latitude - startCoordinate.latitude) * r
            let lon = startCoordinate.longitude + (endCoordinate.longitude - startCoordinate.longitude) * r
            return Coordinate(latitude: lat, longitude: lon)
        }
    }
}

public actor PublicBicycleRoadAPIAdapter {
    public static let shared = PublicBicycleRoadAPIAdapter()
    
    private var serviceKey: String = "8ec0e9a0fe22dfc51687aba0e871c0b8756c66ee81ed6f35e6d17556de07fa67"
    
    public init(serviceKey: String = "8ec0e9a0fe22dfc51687aba0e871c0b8756c66ee81ed6f35e6d17556de07fa67") {
        self.serviceKey = serviceKey
    }
    
    public func setServiceKey(_ key: String) {
        self.serviceKey = key
    }
    
    public func fetchNationwideBicycleRoads(pageNo: Int = 1, numOfRows: Int = 100) async throws -> [PublicBicycleRoadRecord] {
        guard let encodedKey = serviceKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://api.data.go.kr/openapi/tn_pubr_public_bcycl_lne_api?serviceKey=\(encodedKey)&type=json&pageNo=\(pageNo)&numOfRows=\(numOfRows)") else {
            return fallbackCatalogRecords()
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 6.0
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseObj = json["response"] as? [String: Any],
                   let body = responseObj["body"] as? [String: Any],
                   let items = body["items"] as? [[String: Any]] {
                    
                    return items.compactMap { item in
                        guard let name = item["bcyclLneNm"] as? String ?? item["roadName"] as? String,
                              let sLatStr = item["bgngLat"] as? String ?? item["startLat"] as? String, let sLat = Double(sLatStr),
                              let sLonStr = item["bgngLot"] as? String ?? item["startLon"] as? String, let sLon = Double(sLonStr),
                              let eLatStr = item["endLat"] as? String, let eLat = Double(eLatStr),
                              let eLonStr = item["endLot"] as? String ?? item["endLon"] as? String, let eLon = Double(eLonStr) else {
                            return nil
                        }
                        
                        let lengthKM = Double(item["bcyclLneLt"] as? String ?? "1.0") ?? 1.0
                        let startAddr = item["bgngLnmAdr"] as? String ?? "기점"
                        let endAddr = item["endLnmAdr"] as? String ?? "종점"
                        let type = item["bcyclLneSe"] as? String ?? "자전거도로"
                        
                        return PublicBicycleRoadRecord(
                            roadName: name,
                            startAddress: startAddr,
                            endAddress: endAddr,
                            startCoordinate: Coordinate(latitude: sLat, longitude: sLon),
                            endCoordinate: Coordinate(latitude: eLat, longitude: eLon),
                            totalLengthKM: lengthKM,
                            roadType: type
                        )
                    }
                }
            }
        } catch {
            // Fallback to local Hwaseong Bike Road Catalog
        }
        
        return fallbackCatalogRecords()
    }
    
    private func fallbackCatalogRecords() -> [PublicBicycleRoadRecord] {
        return [
            PublicBicycleRoadRecord(
                roadName: "동탄원천로 자전거길",
                startAddress: "경기도 화성시 반정동 73-25",
                endAddress: "경기도 화성시 반월동 640-8",
                startCoordinate: Coordinate(latitude: 37.235898, longitude: 127.035530),
                endCoordinate: Coordinate(latitude: 37.218844, longitude: 127.056421),
                totalLengthKM: 3.9,
                roadType: "자전거 전용도로"
            ),
            PublicBicycleRoadRecord(
                roadName: "병점중앙로 자전거길",
                startAddress: "경기도 화성시 진안동 934-4",
                endAddress: "경기도 화성시 능동 674-6",
                startCoordinate: Coordinate(latitude: 37.219265, longitude: 127.038338),
                endCoordinate: Coordinate(latitude: 37.203703, longitude: 127.036575),
                totalLengthKM: 2.1,
                roadType: "자전거/보행자 겸용"
            ),
            PublicBicycleRoadRecord(
                roadName: "오산천 수변 자전거길",
                startAddress: "경기도 화성시 석우동 오산천",
                endAddress: "경기도 화성시 반송동 오산천",
                startCoordinate: Coordinate(latitude: 37.228500, longitude: 127.072200),
                endCoordinate: Coordinate(latitude: 37.198200, longitude: 127.071100),
                totalLengthKM: 3.4,
                roadType: "수변 자전거 전용도로"
            )
        ]
    }
}

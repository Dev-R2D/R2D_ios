#if canImport(UIKit)
import UIKit
import CoreLocation
import R2DCore

#if canImport(GoogleMaps)
import GoogleMaps
#endif
#if canImport(iNaviMaps)
import iNaviMaps
#endif

public final class R2DMapViewController: UIViewController {
    private static let defaultCenter = Coordinate(latitude: 37.566535, longitude: 126.977969)
    private let route: Route?
    private let routes: [Route]
    private let initialCurrentLocation: Coordinate?
    private let followsUserLocation: Bool
    private let onRouteSelected: ((Route) -> Void)?
    private let rideStateProvider: ActiveRideCoordinator?
    private let locationManager = CLLocationManager()
    private var didCenterOnUserLocation = false
    private var selectedRouteID: String?
    private var rideStateUnsubscribe: Unsubscribe?
    #if canImport(GoogleMaps)
    private weak var googleMapView: GMSMapView?
    private var googleRoutePolylineMap: [String: GMSPolyline] = [:]
    private var googleRoutePolylines: [GMSPolyline] = []
    private var googleRouteIndexMap: [String: Int] = [:]
    private var googleRouteStartMarker: GMSMarker?
    private var googleRouteEndMarker: GMSMarker?
    private var googleUserLocationMarker: GMSMarker?
    #endif
    #if canImport(iNaviMaps)
    private weak var mapView: InaviMapView?
    private var routePolylines: [INVPolyline] = []
    private var routePolylineMap: [String: INVPolyline] = [:]
    private var routePolylineIndexMap: [String: Int] = [:]
    private var routeStartMarker: INVMarker?
    private var routeEndMarker: INVMarker?
    private var userLocationMarker: INVMarker?
    private let infoWindowDataSource = R2DInfoWindowDataSource()
    private var routeStartInfoWindow: INVInfoWindow?
    private var clusterManager: INVClusterManager?
    private var clusterItems: [R2DClusterItem] = []
    #endif

    public init(
        route: Route? = nil,
        routes: [Route] = [],
        initialCurrentLocation: Coordinate? = nil,
        followsUserLocation: Bool = true,
        rideStateProvider: ActiveRideCoordinator? = nil,
        onRouteSelected: ((Route) -> Void)? = nil
    ) {
        self.route = route
        self.routes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        self.initialCurrentLocation = initialCurrentLocation
        self.followsUserLocation = followsUserLocation
        self.rideStateProvider = rideStateProvider
        self.onRouteSelected = onRouteSelected
        selectedRouteID = route?.id ?? routes.first?.id
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.13, blue: 0.15, alpha: 1)
        title = "R2D 지도"
        installMapView()
        bindRideStateIfNeeded()
        startUserLocationUpdates()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        locationManager.stopUpdatingLocation()
    }

    deinit {
        rideStateUnsubscribe?()
    }

    private func installMapView() {
        #if canImport(GoogleMaps)
        let center = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let camera = GMSCameraPosition.camera(withLatitude: center.latitude, longitude: center.longitude, zoom: 14)
        let mapView = GMSMapView(frame: view.bounds, camera: camera)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.settings.myLocationButton = true
        view.addSubview(mapView)
        googleMapView = mapView

        addGoogleRoutePolyline(on: mapView)
        addGoogleRouteMarkers(on: mapView)
        fitGoogleCameraToRoute(on: mapView)
        #elseif canImport(iNaviMaps)
        let options = INVMapOptions()
        options.mapType = .normal
        let initialCenter = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        options.camera = INVCameraPosition(
            INVLatLng(lat: initialCenter.latitude, lng: initialCenter.longitude),
            zoom: 14
        )

        let mapView = InaviMapView(frame: view.bounds, options: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        self.mapView = mapView

        configureMapView(mapView)
        logCoordinateConversionSample()
        addRoutePolyline(on: mapView)
        addRouteMarkers(on: mapView)
        fitCameraToRoute(on: mapView)
        configureInfoWindow(on: mapView)
        configureClusterManager(on: mapView)
        #else
        let label = UILabel()
        label.text = "iNavi 지도 모듈을 연결하면 여기에 지도가 표시됩니다."
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        #endif
    }

    private func selectRoute(_ route: Route) {
        selectedRouteID = route.id
        #if canImport(GoogleMaps)
        refreshGoogleRoutePolylineStyles()
        #endif
        #if canImport(iNaviMaps)
        refreshRoutePolylineStyles()
        #endif
        onRouteSelected?(route)
    }

    #if canImport(GoogleMaps)
    private func addGoogleRouteMarkers(on mapView: GMSMapView) {
        let start = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let startMarker = GMSMarker(position: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
        startMarker.title = route == nil ? "현재 위치 대기" : "R2D 경로 출발"
        startMarker.icon = GMSMarker.markerImage(with: .systemRed)
        startMarker.map = mapView
        googleRouteStartMarker = startMarker

        guard let end = route?.polyline.last ?? routes.first?.polyline.last,
              end != start else { return }
        let endMarker = GMSMarker(position: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude))
        endMarker.title = "R2D 경로 도착"
        endMarker.icon = GMSMarker.markerImage(with: .systemBlue)
        endMarker.map = mapView
        googleRouteEndMarker = endMarker
    }

    private func addGoogleRoutePolyline(on mapView: GMSMapView) {
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemBlue, .systemPurple, .systemTeal, .systemPink]
        for (index, value) in visibleRoutes.enumerated() {
            guard value.polyline.count >= 2 else { continue }
            let path = GMSMutablePath()
            let displayPolyline = displayPolyline(for: value, routeIndex: index, totalRoutes: visibleRoutes.count)
            for point in displayPolyline {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            let polyline = GMSPolyline(path: path)
            let color = colors[index % colors.count]
            let isSelected = value.id == selectedRouteID || (selectedRouteID == nil && index == 0)
            polyline.strokeWidth = isSelected ? 8 : 5
            polyline.strokeColor = color.withAlphaComponent(isSelected ? 0.95 : 0.50)
            polyline.geodesic = true
            polyline.isTappable = true
            polyline.userData = value.id
            polyline.map = mapView
            googleRoutePolylineMap[value.id] = polyline
            googleRouteIndexMap[value.id] = index
            googleRoutePolylines.append(polyline)
        }
    }

    private func fitGoogleCameraToRoute(on mapView: GMSMapView) {
        let coordinates = routes.flatMap(\.polyline).isEmpty ? route?.polyline ?? [] : routes.flatMap(\.polyline)
        guard coordinates.count >= 2 else { return }
        var bounds = GMSCoordinateBounds()
        for coordinate in coordinates {
            bounds = bounds.includingCoordinate(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let update = GMSCameraUpdate.fit(bounds, withPadding: 42)
        mapView.moveCamera(update)
    }

    private func refreshGoogleRoutePolylineStyles() {
        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemBlue, .systemPurple, .systemTeal, .systemPink]
        for (index, value) in routes.enumerated() {
            guard let polyline = googleRoutePolylineMap[value.id] else { continue }
            let isSelected = value.id == selectedRouteID
            polyline.strokeWidth = isSelected ? 8 : 5
            polyline.strokeColor = colors[index % colors.count].withAlphaComponent(isSelected ? 0.95 : 0.50)
            polyline.zIndex = Int32(isSelected ? 100 : (10 + index))
        }
    }

    private func updateGoogleUserLocationMarker(_ location: CLLocation) {
        guard let mapView = googleMapView else { return }
        let position = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if let marker = googleUserLocationMarker {
            marker.position = position
        } else {
            let marker = GMSMarker(position: position)
            marker.title = "내 위치"
            marker.icon = GMSMarker.markerImage(with: .systemRed)
            marker.map = mapView
            googleUserLocationMarker = marker
        }

        guard followsUserLocation, !didCenterOnUserLocation else { return }
        didCenterOnUserLocation = true
        mapView.animate(toLocation: position)
    }
    #endif

    #if canImport(iNaviMaps)
    private func configureMapView(_ mapView: InaviMapView) {
        mapView.delegate = self
        mapView.mapType = .normal

        mapView.showCompass = true
        mapView.showScaleBar = true
        mapView.showZoomControl = true
        mapView.showLocationButton = true

        mapView.isScrollGesturesEnabled = true
        mapView.isZoomGesturesEnabled = true
        mapView.isRotateGesturesEnabled = false
        mapView.isTiltGesturesEnabled = false

        mapView.userTrackingMode = .tracking

        let center = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let cameraUpdate = INVCameraUpdate(targetTo: INVLatLng(lat: center.latitude, lng: center.longitude))
        cameraUpdate.animation = .easeOut
        cameraUpdate.animationDuration = 1
        mapView.moveCamera(cameraUpdate)
    }

    private func logCoordinateConversionSample() {
        let wgs84 = INVLatLng(lat: Self.defaultCenter.latitude, lng: Self.defaultCenter.longitude)
        let converted = R2DCoordinateConverter.convertFromWGS84(wgs84)
        let utmkToWGS84 = R2DCoordinateConverter.utmkToWGS84(x: converted.utmk.x, y: converted.utmk.y)

        print(
            "R2D coordinate conversion:",
            "KATEC(\(converted.katec.x), \(converted.katec.y))",
            "UTMK(\(converted.utmk.x), \(converted.utmk.y))",
            "TM(\(converted.tm.x), \(converted.tm.y))",
            "GRS80(\(converted.grs80.x), \(converted.grs80.y))",
            "UTMK->WGS84(\(utmkToWGS84.lat), \(utmkToWGS84.lng))"
        )
    }

    private func addRouteMarkers(on mapView: InaviMapView) {
        let start = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let startMarker = INVMarker()
        startMarker.position = INVLatLng(lat: start.latitude, lng: start.longitude)
        startMarker.title = route == nil ? "현재 위치 대기" : "R2D 경로 출발"
        startMarker.touchEvent = { _ in
            print("R2D route marker tapped")
            return true
        }
        startMarker.mapView = mapView
        routeStartMarker = startMarker

        guard let end = route?.polyline.last ?? routes.first?.polyline.last, end != start else { return }
        let endMarker = INVMarker()
        endMarker.position = INVLatLng(lat: end.latitude, lng: end.longitude)
        endMarker.title = "R2D 경로 도착"
        endMarker.mapView = mapView
        routeEndMarker = endMarker
    }

    private func addRoutePolyline(on mapView: InaviMapView) {
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemBlue, .systemPurple, .systemTeal, .systemPink]
        for (index, value) in visibleRoutes.enumerated() {
            guard value.polyline.count >= 2 else { continue }
            let displayPolyline = displayPolyline(for: value, routeIndex: index, totalRoutes: visibleRoutes.count)
            let points = displayPolyline.map { INVLatLng(lat: $0.latitude, lng: $0.longitude) }
            let polyline = INVPolyline(coords: points)
            let color = colors[index % colors.count]
            let isSelected = value.id == selectedRouteID || (selectedRouteID == nil && index == 0)
            polyline.width = isSelected ? 8 : 5
            polyline.color = color.withAlphaComponent(isSelected ? 0.95 : 0.62)
            polyline.capType = .round
            polyline.joinType = .round
            polyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + (isSelected ? 20 : 10 + index)
            polyline.touchEvent = { [weak self] _ in
                self?.selectRoute(value)
                return true
            }
            polyline.mapView = mapView
            routePolylines.append(polyline)
            routePolylineMap[value.id] = polyline
            routePolylineIndexMap[value.id] = index
        }
    }

    private func refreshRoutePolylineStyles() {
        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemBlue, .systemPurple, .systemTeal, .systemPink]
        for (index, value) in routes.enumerated() {
            guard let polyline = routePolylineMap[value.id] else { continue }
            let isSelected = value.id == selectedRouteID
            polyline.width = isSelected ? 8 : 5
            polyline.color = colors[index % colors.count].withAlphaComponent(isSelected ? 0.95 : 0.62)
            polyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + (isSelected ? 20 : 10 + index)
        }
    }

    private func fitCameraToRoute(on mapView: InaviMapView) {
        let coordinates = routes.flatMap(\.polyline).isEmpty ? route?.polyline ?? [] : routes.flatMap(\.polyline)
        guard coordinates.count >= 2 else { return }
        let points = coordinates.map { INVLatLng(lat: $0.latitude, lng: $0.longitude) }
        let bounds = INVLatLngBounds(coords: points)
        let cameraUpdate = INVCameraUpdate(fit: bounds, paddingInsets: UIEdgeInsets(top: 90, left: 42, bottom: 90, right: 42))
        cameraUpdate.animation = .easeOut
        cameraUpdate.animationDuration = 0.9
        mapView.moveCamera(cameraUpdate)
    }

    private func configureInfoWindow(on mapView: InaviMapView) {
        guard let marker = routeStartMarker else { return }

        let infoWindow = INVInfoWindow()
        infoWindow.imageDataSource = infoWindowDataSource
        infoWindow.alpha = 0.95
        infoWindow.marker = marker
        infoWindow.mapView = mapView
        routeStartInfoWindow = infoWindow
    }

    private func configureClusterManager(on mapView: InaviMapView) {
        let manager = INVClusterManager(mapView: mapView)
        manager.delegate = self
        manager.minClusteringCount = 2
        manager.maxDistanceBetweenItems = 120

        let start = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let end = route?.polyline.last ?? routes.first?.polyline.last
        var items = [
            R2DClusterItem(position: INVLatLng(lat: start.latitude, lng: start.longitude), title: "출발 지점"),
            R2DClusterItem(position: INVLatLng(lat: 37.237300, lng: 127.037120), title: "노면 후보 1"),
            R2DClusterItem(position: INVLatLng(lat: 37.238100, lng: 127.038200), title: "노면 후보 2"),
            R2DClusterItem(position: INVLatLng(lat: 37.232950, lng: 127.032900), title: "주의 구간"),
            R2DClusterItem(position: INVLatLng(lat: 37.230900, lng: 127.034400), title: "센서 이벤트")
        ]
        if let end {
            items.append(R2DClusterItem(position: INVLatLng(lat: end.latitude, lng: end.longitude), title: "도착 지점"))
        }

        manager.add(items)
        clusterItems = items
        clusterManager = manager
    }

    private func updateUserLocationMarker(_ location: CLLocation) {
        guard let mapView else { return }
        let position = INVLatLng(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        if let marker = userLocationMarker {
            marker.position = position
        } else {
            let marker = INVMarker()
            marker.position = position
            marker.title = "내 위치"
            marker.mapView = mapView
            userLocationMarker = marker
        }

        guard followsUserLocation, !didCenterOnUserLocation else { return }
        didCenterOnUserLocation = true
        let cameraUpdate = INVCameraUpdate(targetTo: position)
        cameraUpdate.animation = .easeOut
        cameraUpdate.animationDuration = 0.8
        mapView.moveCamera(cameraUpdate)
    }
    #endif

    private func bindRideStateIfNeeded() {
        guard let rideStateProvider else { return }
        rideStateUnsubscribe?()
        rideStateUnsubscribe = rideStateProvider.subscribe { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyRideState(state)
            }
        }
    }

    @MainActor
    private func applyRideState(_ state: ActiveRideState) {
        #if canImport(GoogleMaps)
        if let coordinate = state.mapState.currentLocation ?? state.location.coordinate {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            updateGoogleUserLocationMarker(location)
        }

        if let selectedRoute = state.selectedRoute, selectedRoute.id != selectedRouteID {
            selectedRouteID = selectedRoute.id
            refreshGoogleRoutePolylineStyles()
        }

        if followsUserLocation, let camera = state.mapState.camera, let mapView = googleMapView {
            let update = GMSCameraUpdate.setTarget(
                CLLocationCoordinate2D(latitude: camera.center.latitude, longitude: camera.center.longitude),
                zoom: mapView.camera.zoom
            )
            mapView.animate(with: update)
        }
        #endif
        #if canImport(iNaviMaps)
        guard let mapView else { return }

        if let coordinate = state.mapState.currentLocation ?? state.location.coordinate {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            updateUserLocationMarker(location)
        }

        if let selectedRoute = state.selectedRoute, selectedRoute.id != selectedRouteID {
            selectedRouteID = selectedRoute.id
            refreshRoutePolylineStyles()
        }

        guard followsUserLocation, let camera = state.mapState.camera else { return }
        let cameraUpdate = INVCameraUpdate(
            targetTo: INVLatLng(lat: camera.center.latitude, lng: camera.center.longitude)
        )
        cameraUpdate.animation = .linear
        cameraUpdate.animationDuration = 0.6
        mapView.moveCamera(cameraUpdate)
        #endif
    }

    private func startUserLocationUpdates() {
        guard followsUserLocation else { return }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionMessage()
        @unknown default:
            break
        }
    }

    private func showLocationPermissionMessage() {
        let alert = UIAlertController(title: "위치 권한 필요", message: "지도에서 실시간 내 위치를 보려면 위치 권한을 허용해 주세요.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func displayPolyline(for route: Route, routeIndex: Int, totalRoutes: Int) -> [Coordinate] {
        guard totalRoutes > 1 else { return route.polyline }
        let offsetMeters = lateralOffsetMeters(for: route.providerOption, routeIndex: routeIndex)
        guard abs(offsetMeters) > 0.1 else { return route.polyline }
        return shiftedPolyline(route.polyline, lateralOffsetMeters: offsetMeters)
    }

    private func lateralOffsetMeters(for option: String?, routeIndex: Int) -> Double {
        switch option {
        case "pm", "pm_recommendation":
            return 0
        case "pm_main_road":
            return 10
        case "pm_short_distance_priority":
            return -10
        default:
            let centeredIndex = Double(routeIndex) - Double(max(routes.count - 1, 0)) / 2
            return centeredIndex * 8
        }
    }

    private func shiftedPolyline(_ coordinates: [Coordinate], lateralOffsetMeters: Double) -> [Coordinate] {
        guard coordinates.count >= 2 else { return coordinates }
        var shifted: [Coordinate] = []
        shifted.reserveCapacity(coordinates.count)

        for index in coordinates.indices {
            let current = coordinates[index]
            let previous = coordinates[max(0, index - 1)]
            let next = coordinates[min(coordinates.count - 1, index + 1)]
            let heading = headingDegrees(from: previous, to: next)
            shifted.append(offsetCoordinate(current, headingDegrees: heading + 90, distanceMeters: lateralOffsetMeters))
        }

        return shifted
    }

    private func headingDegrees(from start: Coordinate, to end: Coordinate) -> Double {
        let delta = (end.longitude - start.longitude) * .pi / 180
        let latitudeA = start.latitude * .pi / 180
        let latitudeB = end.latitude * .pi / 180
        let y = sin(delta) * cos(latitudeB)
        let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func offsetCoordinate(_ coordinate: Coordinate, headingDegrees: Double, distanceMeters: Double) -> Coordinate {
        let radians = headingDegrees * .pi / 180
        let dLat = (distanceMeters * cos(radians)) / 111_320
        let metersPerLng = max(1, 111_320 * cos(coordinate.latitude * .pi / 180))
        let dLng = (distanceMeters * sin(radians)) / metersPerLng
        return Coordinate(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLng)
    }
}

#if canImport(iNaviMaps)
private final class R2DInfoWindowDataSource: NSObject, INVImageTextDataSource {
    nonisolated func title(with shape: INVShape) -> String {
        if let infoWindow = shape as? INVInfoWindow {
            return String(format: "R2D 출발 지점\n%.5f, %.5f", infoWindow.position.lat, infoWindow.position.lng)
        }
        return "R2D 정보"
    }
}

private final class R2DClusterItem: NSObject, INVClusterItem {
    let position: INVLatLng
    let title: String

    init(position: INVLatLng, title: String) {
        self.position = position
        self.title = title
        super.init()
    }
}

extension R2DMapViewController: @preconcurrency INVMapViewDelegate {
    nonisolated public func mapView(_ mapView: InaviMapView, didUpdateUserLocation userLocation: CLLocation?) {
        guard let location = userLocation else { return }
        print("R2D user location:", location.coordinate.latitude, location.coordinate.longitude)
    }
}

extension R2DMapViewController: @preconcurrency INVClusterManagerDelegate {
    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, willRender cluster: INVCluster, with markerOptions: INVMarkerOptions) {
        markerOptions.position = cluster.position
        markerOptions.title = "\(cluster.count)"
        markerOptions.titleColor = .white
        markerOptions.titleHaloColor = .systemBlue
        markerOptions.titleSize = 14
    }

    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, willRenderClusterItem clusterItem: INVClusterItem, with markerOptions: INVMarkerOptions) {
        markerOptions.position = clusterItem.position
        if let item = clusterItem as? R2DClusterItem {
            markerOptions.title = item.title
        }
        markerOptions.titleColor = .black
        markerOptions.titleHaloColor = .white
        markerOptions.titleSize = 12
    }

    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, didTap cluster: INVCluster, with markerOptions: INVMarkerOptions) -> Bool {
        print("R2D cluster tapped:", cluster.count)
        return true
    }

    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, didTap clusterItem: INVClusterItem, with markerOptions: INVMarkerOptions) -> Bool {
        if let item = clusterItem as? R2DClusterItem {
            print("R2D cluster item tapped:", item.title)
        }
        return true
    }
}
#endif

extension R2DMapViewController: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionMessage()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        #if canImport(GoogleMaps)
        updateGoogleUserLocationMarker(location)
        #endif
        #if canImport(iNaviMaps)
        updateUserLocationMarker(location)
        #endif
    }
}

#if canImport(GoogleMaps)
extension R2DMapViewController: @preconcurrency GMSMapViewDelegate {
    public func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
        guard let polyline = overlay as? GMSPolyline,
              let routeID = polyline.userData as? String,
              let route = routes.first(where: { $0.id == routeID }) else { return }
        selectRoute(route)
    }
}
#endif
#endif

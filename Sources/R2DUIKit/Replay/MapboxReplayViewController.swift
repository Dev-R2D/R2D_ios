#if canImport(UIKit) && canImport(WebKit)
import Foundation
import R2DCore
import UIKit
import WebKit

public final class R2DReplayViewController: UIViewController {
    private let route: Route
    private let routes: [Route]
    private let autoPlay: Bool
    private let webView: WKWebView

    private let headerCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bannerHandleRow = UIStackView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let statePill = PaddingLabel()
    private let metaLabel = UILabel()
    private let routePicker = UISegmentedControl(items: [])
    private let miniSummaryLabel = UILabel()

    private let progressCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let progressTitleLabel = UILabel()
    private let progressPercentLabel = UILabel()
    private let progressHintLabel = UILabel()
    private let speedLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)

    private let routeTypeCard = MetricCardView(title: "경로 유형")
    private let distanceCard = MetricCardView(title: "총 거리")
    private let durationCard = MetricCardView(title: "예상 시간")

    private let playButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let bannerToggleButton = UIButton(type: .system)
    private let headerExpandedContent = UIView()

    private var selectedIndex = 0
    private var progressTimer: Timer?
    private var totalSteps = 220
    private var currentStep = 0
    private var bannersCollapsed = false
    private var headerTopConstraint: NSLayoutConstraint?
    private var progressTopConstraint: NSLayoutConstraint?

    public init(route: Route, routes: [Route], autoPlay: Bool = false) {
        self.route = route
        self.routes = routes.isEmpty ? [route] : routes
        self.autoPlay = autoPlay
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "3D 리플레이"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        view.backgroundColor = .black
        configureView()
        loadMapHTML()
        updateSelection(index: initialSelectedIndex, resetProgress: true)
        if autoPlay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.playReplay()
            }
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopReplay()
    }

    private var initialSelectedIndex: Int {
        routes.firstIndex(where: { $0.id == route.id }) ?? 0
    }

    private var selectedRoute: Route {
        routes[selectedIndex]
    }

    private func configureView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        configureHeaderCard()
        configureProgressCard()
        configureButtons()
    }

    private func configureHeaderCard() {
        headerCard.translatesAutoresizingMaskIntoConstraints = false
        headerCard.layer.cornerRadius = 24
        headerCard.layer.cornerCurve = .continuous
        headerCard.clipsToBounds = true
        view.addSubview(headerCard)

        bannerHandleRow.translatesAutoresizingMaskIntoConstraints = false
        bannerHandleRow.axis = .horizontal
        bannerHandleRow.alignment = .center
        bannerHandleRow.spacing = 10

        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.text = "R2D REPLAY"
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .black)
        eyebrowLabel.textColor = .white.withAlphaComponent(0.55)

        miniSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        miniSummaryLabel.font = .systemFont(ofSize: 13, weight: .bold)
        miniSummaryLabel.textColor = .white.withAlphaComponent(0.82)
        miniSummaryLabel.isHidden = true

        var toggleConfig = UIButton.Configuration.plain()
        toggleConfig.baseForegroundColor = .white.withAlphaComponent(0.88)
        toggleConfig.image = UIImage(systemName: "chevron.up")
        toggleConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        bannerToggleButton.configuration = toggleConfig
        bannerToggleButton.addTarget(self, action: #selector(toggleBanners), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "3D 리플레이"
        titleLabel.font = .systemFont(ofSize: 30, weight: .black)
        titleLabel.textColor = .white

        statePill.translatesAutoresizingMaskIntoConstraints = false
        statePill.text = "준비됨"
        statePill.font = .systemFont(ofSize: 12, weight: .bold)
        statePill.textColor = UIColor(red: 0.49, green: 0.95, blue: 0.77, alpha: 1)
        statePill.backgroundColor = UIColor(red: 0.26, green: 0.50, blue: 0.45, alpha: 0.72)
        statePill.insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        statePill.layer.cornerRadius = 24
        statePill.clipsToBounds = true

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        metaLabel.textColor = .white.withAlphaComponent(0.85)
        metaLabel.numberOfLines = 0

        routePicker.translatesAutoresizingMaskIntoConstraints = false
        routePicker.backgroundColor = .white.withAlphaComponent(0.08)
        routePicker.selectedSegmentTintColor = UIColor(red: 0.21, green: 0.83, blue: 0.60, alpha: 1)
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.78),
            .font: UIFont.systemFont(ofSize: 13, weight: .bold)
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.black.withAlphaComponent(0.82),
            .font: UIFont.systemFont(ofSize: 13, weight: .black)
        ]
        routePicker.setTitleTextAttributes(normalAttrs, for: .normal)
        routePicker.setTitleTextAttributes(selectedAttrs, for: .selected)
        routePicker.addTarget(self, action: #selector(routeChanged), for: .valueChanged)
        routes.enumerated().forEach { index, route in
            routePicker.insertSegment(withTitle: Self.displayName(for: route), at: index, animated: false)
        }

        let headerContent = headerCard.contentView
        headerExpandedContent.translatesAutoresizingMaskIntoConstraints = false
        headerContent.addSubview(bannerHandleRow)
        headerContent.addSubview(headerExpandedContent)
        bannerHandleRow.addArrangedSubview(eyebrowLabel)
        bannerHandleRow.addArrangedSubview(UIView())
        bannerHandleRow.addArrangedSubview(miniSummaryLabel)
        bannerHandleRow.addArrangedSubview(bannerToggleButton)
        [titleLabel, statePill, metaLabel, routePicker].forEach { headerExpandedContent.addSubview($0) }

        NSLayoutConstraint.activate([
            headerCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            headerCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            bannerHandleRow.leadingAnchor.constraint(equalTo: headerContent.leadingAnchor, constant: 18),
            bannerHandleRow.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor, constant: -12),
            bannerHandleRow.topAnchor.constraint(equalTo: headerContent.topAnchor, constant: 14),

            headerExpandedContent.leadingAnchor.constraint(equalTo: headerContent.leadingAnchor),
            headerExpandedContent.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor),
            headerExpandedContent.topAnchor.constraint(equalTo: bannerHandleRow.bottomAnchor, constant: 8),
            headerExpandedContent.bottomAnchor.constraint(equalTo: headerContent.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: headerExpandedContent.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: headerExpandedContent.topAnchor, constant: 6),

            statePill.trailingAnchor.constraint(equalTo: headerExpandedContent.trailingAnchor, constant: -18),
            statePill.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            metaLabel.leadingAnchor.constraint(equalTo: headerExpandedContent.leadingAnchor, constant: 18),
            metaLabel.trailingAnchor.constraint(equalTo: headerExpandedContent.trailingAnchor, constant: -18),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),

            routePicker.leadingAnchor.constraint(equalTo: headerExpandedContent.leadingAnchor, constant: 18),
            routePicker.trailingAnchor.constraint(equalTo: headerExpandedContent.trailingAnchor, constant: -18),
            routePicker.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 14),
            routePicker.heightAnchor.constraint(equalToConstant: 34),
            routePicker.bottomAnchor.constraint(equalTo: headerExpandedContent.bottomAnchor, constant: -18)
        ])
        headerTopConstraint = headerCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14)
        headerTopConstraint?.isActive = true
    }

    private func configureProgressCard() {
        progressCard.translatesAutoresizingMaskIntoConstraints = false
        progressCard.layer.cornerRadius = 24
        progressCard.layer.cornerCurve = .continuous
        progressCard.clipsToBounds = true
        view.addSubview(progressCard)

        [progressTitleLabel, progressPercentLabel, progressHintLabel, speedLabel, progressView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        progressTitleLabel.font = .systemFont(ofSize: 18, weight: .black)
        progressTitleLabel.textColor = .white
        progressTitleLabel.text = "준비됨"

        progressPercentLabel.font = .systemFont(ofSize: 16, weight: .black)
        progressPercentLabel.textColor = .white
        progressPercentLabel.textAlignment = .right
        progressPercentLabel.text = "0%"

        progressHintLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        progressHintLabel.textColor = .white.withAlphaComponent(0.70)
        progressHintLabel.numberOfLines = 0

        speedLabel.font = .systemFont(ofSize: 13, weight: .bold)
        speedLabel.textColor = .white.withAlphaComponent(0.72)
        speedLabel.textAlignment = .right
        speedLabel.text = "재생 x1.0"

        progressView.trackTintColor = .white.withAlphaComponent(0.16)
        progressView.progressTintColor = UIColor(red: 0.25, green: 0.84, blue: 0.86, alpha: 1)
        progressView.progress = 0

        let statsStack = UIStackView(arrangedSubviews: [routeTypeCard, distanceCard, durationCard])
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        statsStack.axis = .horizontal
        statsStack.spacing = 10
        statsStack.distribution = .fillEqually

        let progressContent = progressCard.contentView
        [progressTitleLabel, progressPercentLabel, progressHintLabel, speedLabel, progressView, statsStack].forEach {
            progressContent.addSubview($0)
        }

        NSLayoutConstraint.activate([
            progressCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            progressCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            progressTitleLabel.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 18),
            progressTitleLabel.topAnchor.constraint(equalTo: progressContent.topAnchor, constant: 18),

            progressPercentLabel.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -18),
            progressPercentLabel.centerYAnchor.constraint(equalTo: progressTitleLabel.centerYAnchor),

            progressHintLabel.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 18),
            progressHintLabel.topAnchor.constraint(equalTo: progressTitleLabel.bottomAnchor, constant: 10),
            progressHintLabel.trailingAnchor.constraint(equalTo: speedLabel.leadingAnchor, constant: -8),

            speedLabel.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -18),
            speedLabel.centerYAnchor.constraint(equalTo: progressHintLabel.centerYAnchor),
            speedLabel.widthAnchor.constraint(equalToConstant: 84),

            progressView.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 18),
            progressView.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -18),
            progressView.topAnchor.constraint(equalTo: progressHintLabel.bottomAnchor, constant: 14),
            progressView.heightAnchor.constraint(equalToConstant: 8),

            statsStack.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 18),
            statsStack.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -18),
            statsStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 16),
            statsStack.heightAnchor.constraint(equalToConstant: 104),
            statsStack.bottomAnchor.constraint(equalTo: progressContent.bottomAnchor, constant: -18)
        ])
        progressTopConstraint = progressCard.topAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: 14)
        progressTopConstraint?.isActive = true
    }

    private func configureButtons() {
        let controls = UIStackView(arrangedSubviews: [playButton, resetButton])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.axis = .horizontal
        controls.spacing = 12
        controls.distribution = .fillEqually
        view.addSubview(controls)

        configurePrimaryButton(playButton, title: "재생", color: UIColor(red: 0.18, green: 0.78, blue: 0.36, alpha: 0.94), action: #selector(playTapped))
        configurePrimaryButton(resetButton, title: "처음으로", color: UIColor(red: 0.36, green: 0.34, blue: 0.93, alpha: 0.94), action: #selector(resetTapped))

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            controls.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configurePrimaryButton(_ button: UIButton, title: String, color: UIColor, action: Selector) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 20, weight: .black)
        ]))
        button.configuration = config
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func loadMapHTML() {
        let html = makeHTML()
        if let data = html.data(using: .utf8) {
            webView.load(
                data,
                mimeType: "text/html",
                characterEncodingName: "utf-8",
                baseURL: URL(string: "https://localhost/")!
            )
        } else {
            webView.loadHTMLString(html, baseURL: URL(string: "https://localhost/"))
        }
    }

    private func updateSelection(index: Int, resetProgress: Bool) {
        guard routes.indices.contains(index) else { return }
        selectedIndex = index
        routePicker.selectedSegmentIndex = index

        let selected = selectedRoute
        metaLabel.text = "\(Self.subtitle(for: selected)) · \(selected.polyline.count)개 좌표 기록 · 주행 종료 후 자동 생성"
        miniSummaryLabel.text = "\(Self.displayName(for: selected)) · \(Self.durationLabel(for: selected.totalDuration))"
        routeTypeCard.valueLabel.text = Self.displayName(for: selected)
        distanceCard.valueLabel.text = String(format: "%.1fkm", selected.totalDistance / 1000)
        durationCard.valueLabel.text = Self.durationLabel(for: selected.totalDuration)
        progressHintLabel.text = "\(Self.displayName(for: selected)) 기준으로 주행 기록을 따라갑니다."

        if resetProgress {
            currentStep = 0
            progressView.setProgress(0, animated: false)
            progressTitleLabel.text = "준비됨"
            progressPercentLabel.text = "0%"
            statePill.text = "준비됨"
        }
    }

    private func updateProgress(step: Int) {
        let selected = selectedRoute
        let maxStep = max(totalSteps, 1)
        let ratio = min(1, max(0, Float(step) / Float(maxStep)))
        let remainingDistance = selected.totalDistance * Double(1 - ratio)
        let remainingDuration = selected.totalDuration * Double(1 - ratio)
        progressView.setProgress(ratio, animated: true)
        progressPercentLabel.text = "\(Int((ratio * 100).rounded()))%"
        progressTitleLabel.text = "남은 거리 \(String(format: "%.1f", remainingDistance / 1000))km · 남은 시간 \(Self.durationLabel(for: remainingDuration))"
        statePill.text = ratio >= 1 ? "완료" : "재생 중"
        if ratio >= 1 {
            progressHintLabel.text = "리플레이가 끝났습니다. 처음으로를 누르면 다시 볼 수 있어요."
        }
    }

    @objc private func routeChanged() {
        stopReplay()
        updateSelection(index: routePicker.selectedSegmentIndex, resetProgress: true)
        webView.evaluateJavaScript("selectRoute('\(selectedRoute.id)');", completionHandler: nil)
    }

    @objc private func playTapped() {
        playReplay()
    }

    @objc private func resetTapped() {
        stopReplay()
        updateSelection(index: selectedIndex, resetProgress: true)
        webView.evaluateJavaScript("resetReplay();", completionHandler: nil)
    }

    @objc private func toggleBanners() {
        bannersCollapsed.toggle()
        bannerToggleButton.configuration?.image = UIImage(systemName: bannersCollapsed ? "chevron.down" : "chevron.up")
        miniSummaryLabel.isHidden = !bannersCollapsed

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
            self.progressCard.alpha = self.bannersCollapsed ? 0 : 1
            self.progressCard.transform = self.bannersCollapsed ? CGAffineTransform(translationX: 0, y: -18) : .identity
            self.headerExpandedContent.alpha = self.bannersCollapsed ? 0 : 1
            self.headerExpandedContent.transform = self.bannersCollapsed ? CGAffineTransform(translationX: 0, y: -10) : .identity
            self.miniSummaryLabel.alpha = self.bannersCollapsed ? 1 : 0
            self.metaLabel.alpha = self.bannersCollapsed ? 0 : 1
            self.routePicker.alpha = self.bannersCollapsed ? 0 : 1
            self.titleLabel.alpha = self.bannersCollapsed ? 0 : 1
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.headerExpandedContent.isHidden = self.bannersCollapsed
            self.progressCard.isUserInteractionEnabled = !self.bannersCollapsed
            self.progressCard.isHidden = self.bannersCollapsed
        }
    }

    private func playReplay() {
        stopReplay()
        let selected = selectedRoute
        progressTitleLabel.text = "재생 중"
        progressHintLabel.text = "기록된 경로를 따라 카메라와 이동 포인트가 함께 재생됩니다."
        statePill.text = "재생 중"
        totalSteps = max(220, Int(Double(max(selected.polyline.count, 2)) * 1.5))
        currentStep = 0
        webView.evaluateJavaScript("play();", completionHandler: nil)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.currentStep += 1
            self.updateProgress(step: self.currentStep)
            if self.currentStep >= self.totalSteps {
                timer.invalidate()
                self.progressTimer = nil
            }
        }
    }

    private func stopReplay() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func makeHTML() -> String {
        let payload = makePayloadJSON()
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="initial-scale=1,maximum-scale=1,user-scalable=no">
          <link href="https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css" rel="stylesheet">
          <script src="https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js"></script>
          <script src="https://unpkg.com/deck.gl@9.2.1/dist.min.js"></script>
          <style>
            html, body, #map {
              height: 100%;
              margin: 0;
              background: #061114;
            }
            #map canvas {
              outline: none;
            }
            .maplibregl-ctrl-top-right,
            .maplibregl-ctrl-top-left {
              margin-top: 300px;
            }
            .maplibregl-ctrl-bottom-left,
            .maplibregl-ctrl-bottom-right {
              margin-bottom: 96px;
            }
          </style>
        </head>
        <body>
          <div id="map"></div>
          <script>
            const data = \(payload);
            const {MapboxOverlay, PathLayer, TripsLayer, ScatterplotLayer} = deck;
            let selectedRouteID = data.selectedRouteID;
            let selected = data.routes.find(r => r.id === selectedRouteID) || data.routes[0];
            let coords = selected.coordinates;
            let map;
            let overlay;
            let animationFrame = null;
            let progress = 0;
            let currentTime = 0;

            map = new maplibregl.Map({
              container: 'map',
              style: {
                version: 8,
                sources: {
                  osm: {
                    type: 'raster',
                    tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
                    tileSize: 256,
                    attribution: '© OpenStreetMap contributors'
                  }
                },
                layers: [{ id: 'osm-base', type: 'raster', source: 'osm' }]
              },
              center: coords[0],
              zoom: 15.6,
              pitch: 78,
              bearing: -28,
              attributionControl: true
            });

            function makeTripData(route) {
              return [{
                path: route.coordinates,
                timestamps: route.coordinates.map((_, index) => index),
                color: hexToRgb(route.color)
              }];
            }

            function layersForCurrentState() {
              const pathLayers = data.routes.map(route => new PathLayer({
                id: `path-${route.id}`,
                data: [{path: route.coordinates}],
                getPath: d => d.path,
                getColor: route.id === selectedRouteID ? [...hexToRgb(route.color), 235] : [...hexToRgb(route.color), 90],
                getWidth: route.id === selectedRouteID ? 8 : 4,
                widthMinPixels: route.id === selectedRouteID ? 8 : 4,
                capRounded: true,
                jointRounded: true
              }));

              const tripLayer = new TripsLayer({
                id: 'trip-replay',
                data: makeTripData(selected),
                getPath: d => d.path,
                getTimestamps: d => d.timestamps,
                getColor: d => [...d.color, 255],
                opacity: 0.95,
                widthMinPixels: 10,
                rounded: true,
                trailLength: 22,
                currentTime
              });

              const currentCoord = coords[Math.min(Math.floor(currentTime), Math.max(0, coords.length - 1))] || coords[0];
              const markerLayer = new ScatterplotLayer({
                id: 'moving-marker',
                data: currentCoord ? [{position: currentCoord}] : [],
                getPosition: d => d.position,
                getRadius: 18,
                radiusMinPixels: 10,
                getFillColor: [255, 45, 85, 255],
                getLineColor: [255, 255, 255, 255],
                lineWidthMinPixels: 4,
                stroked: true,
                filled: true
              });

              return [...pathLayers, tripLayer, markerLayer];
            }

            function cameraFor(index) {
              const current = coords[Math.min(index, coords.length - 1)];
              const next = coords[Math.min(index + 8, coords.length - 1)];
              const bearing = turfBearing(current, next);
              return { center: current, bearing };
            }

            function fitToSelectedRoute(duration) {
              const bounds = coords.reduce((b, c) => b.extend(c), new maplibregl.LngLatBounds(coords[0], coords[0]));
              map.fitBounds(bounds, { padding: 56, pitch: 76, bearing: -22, duration });
            }

            function refreshOverlay() {
              if (!overlay) return;
              overlay.setProps({ layers: layersForCurrentState() });
            }

            map.on('load', () => {
              overlay = new MapboxOverlay({
                interleaved: false,
                layers: layersForCurrentState()
              });
              map.addControl(overlay);
              fitToSelectedRoute(900);
              if (data.autoPlay) {
                setTimeout(() => play(), 450);
              }
            });

            window.selectRoute = function selectRoute(routeID) {
              selectedRouteID = routeID;
              selected = data.routes.find(r => r.id === selectedRouteID) || data.routes[0];
              coords = selected.coordinates;
              progress = 0;
              currentTime = 0;
              refreshOverlay();
              fitToSelectedRoute(700);
            }

            window.play = function play() {
              cancelAnimationFrame(animationFrame);
              const totalFrames = Math.max(220, coords.length * 1.5);
              function tick() {
                progress = Math.min(1, progress + 1 / totalFrames);
                const index = Math.floor(progress * (coords.length - 1));
                currentTime = index;
                const camera = cameraFor(index);
                refreshOverlay();
                map.easeTo({
                  center: camera.center,
                  bearing: camera.bearing,
                  pitch: 79,
                  zoom: 16.8,
                  duration: 130,
                  easing: t => t
                });
                if (progress < 1) {
                  animationFrame = requestAnimationFrame(tick);
                }
              }
              tick();
            }

            window.resetReplay = function resetReplay() {
              cancelAnimationFrame(animationFrame);
              progress = 0;
              currentTime = 0;
              refreshOverlay();
              fitToSelectedRoute(700);
            }

            function hexToRgb(hex) {
              const clean = hex.replace('#', '');
              const value = parseInt(clean, 16);
              return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
            }

            function turfBearing(a, b) {
              const lon1 = a[0] * Math.PI / 180, lon2 = b[0] * Math.PI / 180;
              const lat1 = a[1] * Math.PI / 180, lat2 = b[1] * Math.PI / 180;
              const y = Math.sin(lon2 - lon1) * Math.cos(lat2);
              const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lon2 - lon1);
              return Math.atan2(y, x) * 180 / Math.PI;
            }
          </script>
        </body>
        </html>
        """
    }

    private func makePayloadJSON() -> String {
        let colors = ["#35d399", "#ff8a22", "#4f8cff"]
        let routePayloads = routes.enumerated().map { index, route in
            [
                "id": route.id,
                "name": Self.displayName(for: route),
                "subtitle": Self.subtitle(for: route),
                "distance": route.totalDistance,
                "duration": route.totalDuration,
                "coordinates": route.polyline.map { [$0.longitude, $0.latitude] },
                "color": colors[index % colors.count]
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "autoPlay": autoPlay,
            "selectedRouteID": selectedRoute.id,
            "routes": routePayloads
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"selectedRouteID":"","routes":[]}"#
        }
        return json
    }

    private static func displayName(for route: Route) -> String {
        switch route.providerOption {
        case "pm": return "PM 추천"
        case "pm_main_road": return "큰길"
        case "pm_short_distance_priority": return "최단"
        default: return route.providerOption ?? "선택 경로"
        }
    }

    private static func subtitle(for route: Route) -> String {
        switch route.providerOption {
        case "pm": return "PM 추천 경로"
        case "pm_main_road": return "큰길 위주 경로"
        case "pm_short_distance_priority": return "최단 거리 경로"
        default: return "선택한 경로"
        }
    }

    private static func durationLabel(for duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes)분"
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

private final class MetricCardView: UIView {
    let titleLabel = UILabel()
    let valueLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white.withAlphaComponent(0.06)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        layer.borderWidth = 1

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white.withAlphaComponent(0.58)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 18, weight: .black)
        valueLabel.textColor = .white
        valueLabel.numberOfLines = 2

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
#endif

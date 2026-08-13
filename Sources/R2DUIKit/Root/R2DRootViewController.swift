#if canImport(UIKit)
import Combine
import R2DAppSupport
import R2DCore
import UIKit

public final class R2DRootViewController: UIViewController {
    private let model: RideViewModel
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let diagnosticsLabel = UILabel()
    private let locationStatusLabel = UILabel()
    private let navigationModeLabel = UILabel()
    private let navigationInstructionLabel = UILabel()
    private let navigationMetricsLabel = UILabel()
    private let navigationProgressView = UIProgressView(progressViewStyle: .bar)
    private let remainingDistanceLabel = UILabel()
    private let remainingDurationLabel = UILabel()
    private let riskWarningLabel = UILabel()
    private let sessionNoticeLabel = UILabel()
    private let routeLabel = UILabel()
    private let routeDetailLabel = UILabel()
    private let originField = UITextField()
    private let destinationField = UITextField()
    private let searchOriginButton = UIButton(type: .system)
    private let searchDestinationButton = UIButton(type: .system)
    private let routeOptionControl = UISegmentedControl(items: ["PM 추천", "큰길", "최단"])
    private let demoDistanceControl = UISegmentedControl(items: ["1km", "3km", "5km", "전체"])
    private let routeSearchButton = UIButton(type: .system)
    private let mapMatchButton = UIButton(type: .system)
    private let searchMessageLabel = UILabel()
    private let originResultButton = UIButton(type: .system)
    private let destinationResultButton = UIButton(type: .system)
    private let mapPreview = UIView()
    private let mapHintLabel = UILabel()
    private let navigationPanel = UIStackView()
    private let setupPanel = UIStackView()
    private let startButton = UIButton(type: .system)
    private let finishButton = UIButton(type: .system)
    private let gameButton = UIButton(type: .system)
    private var embeddedMapController: R2DMapViewController?
    private var embeddedRouteID: String?
    private var isPresentingReplay = false

    public init(model: RideViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        bindModel()
        observeKeyboard()
        model.bootstrap()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureView() {
        view.backgroundColor = UIColor(red: 0.035, green: 0.07, blue: 0.09, alpha: 1)

        titleLabel.text = "R2D Navigator"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8

        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = .systemGreen
        statusLabel.numberOfLines = 0

        diagnosticsLabel.text = model.diagnosticsSummary
        diagnosticsLabel.font = .systemFont(ofSize: 10, weight: .regular)
        diagnosticsLabel.textColor = .white.withAlphaComponent(0.45)
        diagnosticsLabel.numberOfLines = 0

        locationStatusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        locationStatusLabel.textColor = .white.withAlphaComponent(0.66)
        locationStatusLabel.numberOfLines = 0

        navigationModeLabel.text = "NAVIGATOR"
        navigationModeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        navigationModeLabel.textColor = .systemGreen
        navigationModeLabel.numberOfLines = 1

        navigationInstructionLabel.text = "경로를 선택한 뒤 주행 시작을 눌러 주세요."
        navigationInstructionLabel.font = .systemFont(ofSize: 28, weight: .bold)
        navigationInstructionLabel.textColor = .white
        navigationInstructionLabel.numberOfLines = 0

        navigationMetricsLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        navigationMetricsLabel.textColor = .systemGreen
        navigationMetricsLabel.numberOfLines = 0

        navigationProgressView.trackTintColor = .white.withAlphaComponent(0.14)
        navigationProgressView.progressTintColor = .systemGreen

        [remainingDistanceLabel, remainingDurationLabel, riskWarningLabel, sessionNoticeLabel].forEach {
            $0.font = .systemFont(ofSize: 13, weight: .semibold)
            $0.textColor = .white.withAlphaComponent(0.72)
            $0.numberOfLines = 0
        }
        riskWarningLabel.textColor = .systemYellow

        routeLabel.font = .systemFont(ofSize: 16, weight: .medium)
        routeLabel.textColor = .white.withAlphaComponent(0.78)
        routeLabel.numberOfLines = 0
        routeDetailLabel.font = .systemFont(ofSize: 13, weight: .medium)
        routeDetailLabel.textColor = .white.withAlphaComponent(0.62)
        routeDetailLabel.numberOfLines = 0
        searchMessageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        searchMessageLabel.textColor = .white.withAlphaComponent(0.72)
        searchMessageLabel.numberOfLines = 0

        configureTextField(originField, placeholder: "출발지 주소")
        configureTextField(destinationField, placeholder: "도착지 주소")
        originField.delegate = self
        destinationField.delegate = self
        originField.text = "서울특별시 종로구 종로3가"
        destinationField.text = "경기도 성남시 분당구 판교역로 240"

        configureButton(searchOriginButton, title: "출발 검색", color: .systemBlue, action: #selector(searchOrigin))
        configureButton(searchDestinationButton, title: "도착 검색", color: .systemBlue, action: #selector(searchDestination))
        configureButton(routeSearchButton, title: "경로 탐색", color: .systemOrange, action: #selector(searchRoute))
        configureButton(mapMatchButton, title: "맵매칭", color: .systemPurple, action: #selector(mapMatchRoute))
        configureResultButton(originResultButton, action: #selector(selectOriginResult))
        configureResultButton(destinationResultButton, action: #selector(selectDestinationResult))
        configureRouteOptionControl()
        configureDemoDistanceControl()

        configureMapPreview()

        configureButton(startButton, title: "주행 시작", color: .systemGreen, action: #selector(startRide))
        configureButton(finishButton, title: "주행 종료", color: .systemRed, action: #selector(finishRide))
        configureButton(gameButton, title: "3D 리플레이", color: .systemIndigo, action: #selector(openReplay))

        let buttonStack = UIStackView(arrangedSubviews: [startButton, finishButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 10
        buttonStack.distribution = .fillEqually

        let originStack = UIStackView(arrangedSubviews: [originField, searchOriginButton])
        originStack.axis = .horizontal
        originStack.spacing = 8
        originStack.distribution = .fill

        let destinationStack = UIStackView(arrangedSubviews: [destinationField, searchDestinationButton])
        destinationStack.axis = .horizontal
        destinationStack.spacing = 8
        destinationStack.distribution = .fill

        let routeActionStack = UIStackView(arrangedSubviews: [routeSearchButton, mapMatchButton])
        routeActionStack.axis = .horizontal
        routeActionStack.spacing = 10
        routeActionStack.distribution = .fillEqually

        setupPanel.axis = .vertical
        setupPanel.spacing = 12
        setupPanel.addArrangedSubview(routeLabel)
        setupPanel.addArrangedSubview(routeDetailLabel)
        setupPanel.addArrangedSubview(originStack)
        setupPanel.addArrangedSubview(originResultButton)
        setupPanel.addArrangedSubview(destinationStack)
        setupPanel.addArrangedSubview(destinationResultButton)
        setupPanel.addArrangedSubview(routeOptionControl)
        setupPanel.addArrangedSubview(demoDistanceControl)
        setupPanel.addArrangedSubview(routeActionStack)
        setupPanel.addArrangedSubview(searchMessageLabel)

        navigationPanel.axis = .vertical
        navigationPanel.spacing = 8
        navigationPanel.isHidden = true
        navigationPanel.addArrangedSubview(navigationModeLabel)
        navigationPanel.addArrangedSubview(navigationInstructionLabel)
        navigationPanel.addArrangedSubview(navigationMetricsLabel)
        navigationPanel.addArrangedSubview(navigationProgressView)
        let navigationMetricStack = UIStackView(arrangedSubviews: [remainingDistanceLabel, remainingDurationLabel])
        navigationMetricStack.axis = .horizontal
        navigationMetricStack.spacing = 10
        navigationMetricStack.distribution = .fillEqually
        navigationPanel.addArrangedSubview(navigationMetricStack)
        navigationPanel.addArrangedSubview(riskWarningLabel)
        navigationPanel.addArrangedSubview(sessionNoticeLabel)

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, diagnosticsLabel, locationStatusLabel, navigationPanel, setupPanel, mapPreview, buttonStack, gameButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            mapPreview.heightAnchor.constraint(equalToConstant: 360),
            startButton.heightAnchor.constraint(equalToConstant: 48),
            gameButton.heightAnchor.constraint(equalToConstant: 48),
            searchOriginButton.widthAnchor.constraint(equalToConstant: 96),
            searchDestinationButton.widthAnchor.constraint(equalToConstant: 96),
            originField.heightAnchor.constraint(equalToConstant: 44),
            destinationField.heightAnchor.constraint(equalToConstant: 44),
            routeOptionControl.heightAnchor.constraint(equalToConstant: 34),
            demoDistanceControl.heightAnchor.constraint(equalToConstant: 34),
            routeSearchButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.backgroundColor = .white
        field.textColor = .black
        field.font = .systemFont(ofSize: 15, weight: .medium)
    }

    private func configureResultButton(_ button: UIButton, action: Selector) {
        var config = UIButton.Configuration.plain()
        config.title = "검색 결과 없음"
        config.baseForegroundColor = .white.withAlphaComponent(0.75)
        config.contentInsets = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 2
        button.addTarget(self, action: action, for: .touchUpInside)
        button.isHidden = true
    }

    private func configureMapPreview() {
        mapPreview.backgroundColor = UIColor(red: 0.08, green: 0.13, blue: 0.15, alpha: 1)
        mapPreview.layer.cornerRadius = 12
        mapPreview.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.25).cgColor
        mapPreview.layer.borderWidth = 1
        mapPreview.clipsToBounds = true
        mapPreview.isUserInteractionEnabled = true
        mapPreview.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openMap)))

        mapHintLabel.text = "경로 지도\n탭하면 전체화면"
        mapHintLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        mapHintLabel.textColor = .white
        mapHintLabel.textAlignment = .center
        mapHintLabel.numberOfLines = 0
        mapHintLabel.translatesAutoresizingMaskIntoConstraints = false
        mapPreview.addSubview(mapHintLabel)

        NSLayoutConstraint.activate([
            mapHintLabel.leadingAnchor.constraint(equalTo: mapPreview.leadingAnchor, constant: 20),
            mapHintLabel.trailingAnchor.constraint(equalTo: mapPreview.trailingAnchor, constant: -20),
            mapHintLabel.centerYAnchor.constraint(equalTo: mapPreview.centerYAnchor)
        ])
    }

    private func configureRouteOptionControl() {
        routeOptionControl.selectedSegmentIndex = 0
        configureSegmentedControl(routeOptionControl, selectedColor: .systemOrange)
        routeOptionControl.addTarget(self, action: #selector(routeOptionChanged), for: .valueChanged)
    }

    private func configureDemoDistanceControl() {
        demoDistanceControl.selectedSegmentIndex = 3
        configureSegmentedControl(demoDistanceControl, selectedColor: .systemGreen)
        demoDistanceControl.addTarget(self, action: #selector(demoDistanceChanged), for: .valueChanged)
    }

    private func configureSegmentedControl(_ control: UISegmentedControl, selectedColor: UIColor) {
        control.backgroundColor = .white.withAlphaComponent(0.08)
        control.selectedSegmentTintColor = selectedColor
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.82), .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .bold)], for: .selected)
    }

    private func configureButton(_ button: UIButton, title: String, color: UIColor, action: Selector) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.titleLineBreakMode = .byTruncatingTail
        button.configuration = config
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.78
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func bindModel() {
        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)

        model.$summary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                guard let summary else { return }
                self?.statusLabel.text = "주행 완료: 유효 거리 \(Int(summary.validDistanceM))m"
            }
            .store(in: &cancellables)

        model.$routeSearchMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.searchMessageLabel.text = message ?? "주소를 검색한 뒤 경로 탐색을 실행하세요." }
            .store(in: &cancellables)

        model.$originResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in self?.renderResult(results.first, button: self?.originResultButton, prefix: "출발") }
            .store(in: &cancellables)

        model.$destinationResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in self?.renderResult(results.first, button: self?.destinationResultButton, prefix: "도착") }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$isSearchingPlaces, model.$isSearchingRoute)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.render(self?.model.state ?? .idle) }
            .store(in: &cancellables)

        model.$isDemoNavigating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render(self?.model.state ?? .idle) }
            .store(in: &cancellables)

        model.$pendingReplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] replay in
                guard let self, let replay else { return }
                self.presentReplay(replay)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: ActiveRideState) {
        let sessionState = state.session?.state.rawValue ?? "READY"
        statusLabel.text = "상태: \(sessionState) · Queue \(state.queuedChunkCount)"
        locationStatusLabel.text = Self.locationStatusText(for: state)

        if let route = state.selectedRoute ?? state.routes.first {
            routeLabel.text = "선택 경로: \(Self.formatDistance(route.totalDistance)) · \(RideViewModel.routeDurationLabel(for: route))"
            routeDetailLabel.text = Self.routeDetailText(for: route, routeCount: state.routes.count)
            routeDetailLabel.isHidden = false
            installEmbeddedMapIfNeeded(route: route, routes: state.routes)
        } else {
            routeLabel.text = "출발지와 도착지를 입력한 뒤 경로 탐색을 눌러 주세요."
            routeDetailLabel.isHidden = true
            installEmbeddedMapIfNeeded(route: nil, routes: [])
        }

        let isNavigating = isNavigatorDrivingMode(state)
        setupPanel.isHidden = isNavigating
        navigationPanel.isHidden = !isNavigating
        diagnosticsLabel.isHidden = isNavigating
        gameButton.isHidden = isNavigating
        if isNavigating {
            renderNavigation(state)
        }

        startButton.isEnabled = !isNavigating
        finishButton.isEnabled = isNavigating
        routeSearchButton.isEnabled = !model.isSearchingRoute
        searchOriginButton.isEnabled = !model.isSearchingPlaces
        searchDestinationButton.isEnabled = !model.isSearchingPlaces
    }

    private func renderNavigation(_ state: ActiveRideState) {
        let sessionText = state.session?.state.rawValue ?? "DEMO"
        navigationModeLabel.text = model.isDemoNavigating && state.session?.state != .active ? "NAVIGATOR · DEMO" : "NAVIGATOR · \(sessionText)"

        let route = state.selectedRoute ?? state.routes.first
        let progress = state.navigationProgress
        let fallbackDistance = route.map { model.displayedDistance(for: $0) } ?? 0
        let fallbackDuration = route.map { model.displayedDuration(for: $0) } ?? 0
        let remainingDistance = progress?.remainingDistance ?? fallbackDistance
        let remainingDuration = progress?.remainingDuration ?? fallbackDuration
        let ratio = Float(min(1, max(0, progress?.progressRatio ?? state.session?.routeProgressRatio ?? 0)))

        if let warning = state.roadWarning {
            navigationInstructionLabel.text = "주의 구간 접근"
            navigationMetricsLabel.text = "\(Self.warningSeverityText(warning.severity)) · \(Self.formatDistance(warning.distanceM)) 앞 · 신뢰도 \(Int(warning.confidence * 100))%"
            riskWarningLabel.text = "안전 경고: \(Self.riskStateText(warning.riskState))"
        } else if state.isRerouting {
            navigationInstructionLabel.text = "경로 재탐색 중"
            navigationMetricsLabel.text = "현재 위치 기준으로 새 경로를 계산하고 있습니다."
            riskWarningLabel.text = "안전 경고 없음"
        } else if let instruction = state.nextInstruction {
            navigationInstructionLabel.text = instruction.title
            navigationMetricsLabel.text = "다음 안내까지 \(Self.formatDistance(instruction.distanceM))"
            riskWarningLabel.text = "안전 경고 없음"
        } else if let route {
            navigationInstructionLabel.text = "경로를 따라 주행 중"
            navigationMetricsLabel.text = Self.routeDetailText(for: route, routeCount: state.routes.count)
            riskWarningLabel.text = "안전 경고 없음"
        } else {
            navigationInstructionLabel.text = "주행 중"
            navigationMetricsLabel.text = locationStatusLabel.text
            riskWarningLabel.text = "안전 경고 없음"
        }

        navigationProgressView.setProgress(ratio, animated: true)
        remainingDistanceLabel.text = "남은 거리\n\(Self.formatDistance(remainingDistance))"
        remainingDurationLabel.text = "예상 시간\n\(Self.formatDuration(remainingDuration))"
        sessionNoticeLabel.text = "데모 주행거리 \(model.demoDistanceLabel) · 서버 확정 전 클라이언트 추정값 · Queue \(state.queuedChunkCount)"
    }

    private func isNavigatorDrivingMode(_ state: ActiveRideState) -> Bool {
        state.session?.state == .active || state.session?.state == .paused || model.isDemoNavigating
    }

    private func renderResult(_ result: PlaceSearchResult?, button: UIButton?, prefix: String) {
        guard let button else { return }
        var config = button.configuration ?? .plain()
        if let result {
            config.title = "\(prefix): \(result.title) [\(result.source)]\n\(result.address)"
            config.baseForegroundColor = .systemGreen
            button.isHidden = false
        } else {
            config.title = "\(prefix): 검색 결과 없음"
            config.baseForegroundColor = .white.withAlphaComponent(0.75)
            button.isHidden = true
        }
        button.configuration = config
    }

    private static func routeDetailText(for route: Route, routeCount: Int) -> String {
        var parts = ["iMPS \(displayRouteOption(route.providerOption))"]
        if routeCount > 1 {
            parts.append("후보 \(routeCount)개")
        }
        parts.append(RideViewModel.isPMRoute(route.providerOption) ? "도보/PM API \(formatDuration(route.totalDuration))" : "차량 API \(formatDuration(route.totalDuration))")
        if let tollFee = route.tollFee {
            parts.append("통행료 \(formatWon(tollFee))")
        }
        if let taxiFare = route.taxiFare {
            parts.append("예상 택시 \(formatWon(taxiFare))")
        } else if let totalTaxiFare = route.totalTaxiFare, !totalTaxiFare.isEmpty {
            parts.append("예상 택시 \(totalTaxiFare)원")
        }
        if route.isHighWay == true {
            parts.append("고속도로 포함")
        }
        return parts.joined(separator: " · ")
    }

    private static func locationStatusText(for state: ActiveRideState) -> String {
        let readiness = state.locationReadiness
        let auth: String
        switch readiness.authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            auth = "권한 허용"
        case .notDetermined:
            auth = "권한 대기"
        case .denied:
            auth = "권한 거부"
        case .restricted:
            auth = "권한 제한"
        }
        guard let coordinate = state.location.coordinate else {
            return "현재 위치: 수신 대기 · \(auth)"
        }
        return String(format: "현재 위치: %.5f, %.5f · %@", coordinate.latitude, coordinate.longitude, auth)
    }

    private static func displayRouteOption(_ option: String?) -> String {
        switch option {
        case "real_traffic": return "실시간 경로"
        case "real_traffic2": return "대안 경로"
        case "real_traffic_freeroad": return "차량 무료도로"
        case "short_distance_priority": return "차량 최단거리"
        case "time_priority": return "최소시간"
        case "motorcycle": return "이륜차"
        case "pm", "pm_recommendation": return "PM 추천"
        case "pm_short_distance_priority": return "PM 최단"
        case "pm_easy_way": return "PM 편한 길"
        case "pm_time_priority": return "PM 최소시간"
        case "pm_main_road": return "PM 큰길"
        case "highway_priority": return "고속도로"
        case "recommendation": return "추천 경로"
        case let value?: return value
        case nil: return "경로"
        }
    }

    private static func warningSeverityText(_ severity: RoadWarningSeverity) -> String {
        switch severity {
        case .informational: return "정보"
        case .caution: return "주의"
        case .high: return "위험"
        }
    }

    private static func riskStateText(_ state: RiskState) -> String {
        switch state {
        case .normal: return "정상"
        case .rough: return "거친 노면"
        case .suspectedDamage: return "파손 의심"
        case .confirmedDamage: return "파손 확정"
        case .repairPending: return "보수 대기"
        case .restricted: return "제한 구간"
        }
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "\(minutes)분"
    }

    private static func formatWon(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: amount)) ?? String(amount))원"
    }

    @objc private func searchOrigin() {
        view.endEditing(true)
        model.searchOrigin(originField.text ?? "")
    }

    @objc private func searchDestination() {
        view.endEditing(true)
        model.searchDestination(destinationField.text ?? "")
    }

    @objc private func selectOriginResult() {
        model.selectOrigin(at: 0)
    }

    @objc private func selectDestinationResult() {
        model.selectDestination(at: 0)
    }

    @objc private func searchRoute() {
        view.endEditing(true)
        model.searchRoute(originQuery: originField.text ?? "", destinationQuery: destinationField.text ?? "")
    }

    @objc private func routeOptionChanged() {
        let options = ["pm", "pm_main_road", "pm_short_distance_priority"]
        guard options.indices.contains(routeOptionControl.selectedSegmentIndex) else { return }
        model.selectRouteOption(options[routeOptionControl.selectedSegmentIndex])
    }

    @objc private func demoDistanceChanged() {
        let distances: [Double?] = [1000, 3000, 5000, nil]
        guard distances.indices.contains(demoDistanceControl.selectedSegmentIndex) else { return }
        model.selectDemoDistance(distances[demoDistanceControl.selectedSegmentIndex])
    }

    @objc private func mapMatchRoute() {
        model.mapMatchSelectedRoute()
    }

    @objc private func startRide() {
        model.startSelectedRoute()
        guard model.state.selectedRoute ?? model.state.routes.first != nil else { return }
        openMap()
    }

    @objc private func finishRide() {
        model.finishRide()
    }

    @objc private func openMap() {
        let map = R2DMapViewController(
            route: model.state.selectedRoute ?? model.state.routes.first,
            routes: model.state.routes,
            initialCurrentLocation: model.state.location.coordinate,
            followsUserLocation: true,
            rideStateProvider: model.coordinator
        ) { [weak self] route in
            self?.model.selectRoute(id: route.id)
        }
        let navigation = UINavigationController(rootViewController: map)
        present(navigation, animated: true)
    }

    private func installEmbeddedMapIfNeeded(route: Route?, routes: [Route]) {
        let routeID = routes.map(\.id).joined(separator: "|")
        let selectedRouteID = route?.id ?? "none"
        let isNavigating = isNavigatorDrivingMode(model.state)
        let previewID = "\(isNavigating ? "navigation" : "preview")-\(selectedRouteID)-\(routeID.isEmpty ? "current-location-preview" : routeID)"
        guard embeddedRouteID != previewID else { return }

        if let embeddedMapController {
            embeddedMapController.willMove(toParent: nil)
            embeddedMapController.view.removeFromSuperview()
            embeddedMapController.removeFromParent()
        }

        mapHintLabel.isHidden = true
        let controller = R2DMapViewController(
            route: route,
            routes: routes,
            initialCurrentLocation: model.state.location.coordinate,
            followsUserLocation: isNavigating,
            rideStateProvider: model.coordinator
        ) { [weak self] route in
            self?.model.selectRoute(id: route.id)
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        mapPreview.insertSubview(controller.view, at: 0)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: mapPreview.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: mapPreview.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: mapPreview.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: mapPreview.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        embeddedMapController = controller
        embeddedRouteID = previewID
    }

    @objc private func openReplay() {
        guard let route = model.state.selectedRoute ?? model.state.routes.first else {
            searchMessageLabel.text = "먼저 경로를 탐색하면 3D 리플레이를 볼 수 있어요."
            return
        }
        presentReplay(.init(route: route, routes: model.state.routes))
    }

    private func presentReplay(_ payload: ReplayPresentation) {
        presentReplay(payload, autoPlay: false)
    }

    private func presentReplay(_ payload: ReplayPresentation, autoPlay: Bool) {
        guard !isPresentingReplay else { return }
        isPresentingReplay = true
        let replay = R2DReplayViewController(route: payload.route, routes: payload.routes, autoPlay: autoPlay)
        let navigation = UINavigationController(rootViewController: replay)
        navigation.presentationController?.delegate = self
        present(navigation, animated: true) { [weak self] in
            self?.model.consumePendingReplay()
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
        scrollView.contentInset.bottom = overlap + 16
        scrollView.verticalScrollIndicatorInsets.bottom = overlap + 16
    }

    @objc private func keyboardWillHide() {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
}

extension R2DRootViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === originField {
            destinationField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            model.searchRoute(originQuery: originField.text ?? "", destinationQuery: destinationField.text ?? "")
        }
        return true
    }
}

extension R2DRootViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresentingReplay = false
    }
}
#endif

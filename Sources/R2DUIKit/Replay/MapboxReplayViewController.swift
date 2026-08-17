#if canImport(UIKit) && canImport(WebKit)
import AVFoundation
import AVKit
import Foundation
import R2DCore
import R2DInfrastructure
import UIKit
import WebKit

public final class R2DReplayViewController: UIViewController {
    private struct ReplayEvent {
        let id: String
        let coordinate: Coordinate
        let score: Double
        let confidence: Double
        let index: Int
        let time: Double?
        let accuracy: Double?
        let speedKmh: Double?
        let peakAcceleration: Double?
        let accelRMS: Double?
        let jerkRMS: Double?
        let gyroRMS: Double?
        let decision: String
        let surfaceLabel: String
        let evidenceSource: String?
    }

    private let route: Route
    private let routes: [Route]
    private let autoPlay: Bool
    private let webView: WKWebView
    private let eventPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let eventImageView = UIImageView()
    private let eventTitleLabel = UILabel()
    private let eventDetailLabel = UILabel()
    private let eventVideoButton = UIButton(type: .system)
    private let eventActionButton = UIButton(type: .system)

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
    private let reportScrollView = UIScrollView()
    private let reportStack = UIStackView()

    private var selectedIndex = 0
    private var progressTimer: Timer?
    private var totalSteps = 220
    private var currentStep = 0
    private var bannersCollapsed = false
    private var headerTopConstraint: NSLayoutConstraint?
    private var progressTopConstraint: NSLayoutConstraint?
    private var replayEvents: [ReplayEvent] { Self.events(from: selectedRoute) }

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
        title = "주행 종료 리포트"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        view.backgroundColor = .black
        selectedIndex = initialSelectedIndex
        configureView()
        renderNativeReport()
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
        reportScrollView.translatesAutoresizingMaskIntoConstraints = false
        reportScrollView.alwaysBounceVertical = true
        reportScrollView.backgroundColor = .black
        view.addSubview(reportScrollView)

        reportStack.translatesAutoresizingMaskIntoConstraints = false
        reportStack.axis = .vertical
        reportStack.spacing = 14
        reportScrollView.addSubview(reportStack)

        NSLayoutConstraint.activate([
            reportScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reportScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reportScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            reportScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            reportStack.leadingAnchor.constraint(equalTo: reportScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            reportStack.trailingAnchor.constraint(equalTo: reportScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            reportStack.topAnchor.constraint(equalTo: reportScrollView.contentLayoutGuide.topAnchor, constant: 18),
            reportStack.bottomAnchor.constraint(equalTo: reportScrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            reportStack.widthAnchor.constraint(equalTo: reportScrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func configureHeaderCard() {
        headerCard.translatesAutoresizingMaskIntoConstraints = false
        headerCard.layer.cornerRadius = 0
        headerCard.layer.cornerCurve = .continuous
        headerCard.clipsToBounds = true
        headerCard.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.70)
        view.addSubview(headerCard)

        bannerHandleRow.translatesAutoresizingMaskIntoConstraints = false
        bannerHandleRow.axis = .horizontal
        bannerHandleRow.alignment = .center
        bannerHandleRow.spacing = 8

        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.text = "R2D RIDE REPORT"
        eyebrowLabel.font = .systemFont(ofSize: 11, weight: .black)
        eyebrowLabel.textColor = .white.withAlphaComponent(0.68)

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
        titleLabel.text = "주행 종료 리포트"
        titleLabel.font = .systemFont(ofSize: 21, weight: .black)
        titleLabel.textColor = .white

        statePill.translatesAutoresizingMaskIntoConstraints = false
        statePill.text = "준비됨"
        statePill.font = .systemFont(ofSize: 12, weight: .bold)
        statePill.textColor = UIColor(red: 0.49, green: 0.95, blue: 0.77, alpha: 1)
        statePill.backgroundColor = UIColor(red: 0.26, green: 0.50, blue: 0.45, alpha: 0.72)
        statePill.insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        statePill.layer.cornerRadius = 24
        statePill.clipsToBounds = true

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .systemFont(ofSize: 13, weight: .semibold)
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
            headerCard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerCard.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            bannerHandleRow.leadingAnchor.constraint(equalTo: headerContent.leadingAnchor, constant: 16),
            bannerHandleRow.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor, constant: -10),
            bannerHandleRow.topAnchor.constraint(equalTo: headerContent.topAnchor, constant: 10),

            headerExpandedContent.leadingAnchor.constraint(equalTo: headerContent.leadingAnchor),
            headerExpandedContent.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor),
            headerExpandedContent.topAnchor.constraint(equalTo: bannerHandleRow.bottomAnchor, constant: 2),
            headerExpandedContent.bottomAnchor.constraint(equalTo: headerContent.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: headerExpandedContent.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: headerExpandedContent.topAnchor, constant: 2),

            statePill.trailingAnchor.constraint(equalTo: headerExpandedContent.trailingAnchor, constant: -16),
            statePill.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            metaLabel.leadingAnchor.constraint(equalTo: headerExpandedContent.leadingAnchor, constant: 16),
            metaLabel.trailingAnchor.constraint(equalTo: headerExpandedContent.trailingAnchor, constant: -16),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            routePicker.leadingAnchor.constraint(equalTo: headerExpandedContent.leadingAnchor, constant: 16),
            routePicker.trailingAnchor.constraint(equalTo: headerExpandedContent.trailingAnchor, constant: -16),
            routePicker.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            routePicker.heightAnchor.constraint(equalToConstant: routes.count > 1 ? 34 : 0),
            routePicker.bottomAnchor.constraint(equalTo: headerExpandedContent.bottomAnchor, constant: -12)
        ])
        routePicker.isHidden = routes.count <= 1
        headerTopConstraint = headerCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        headerTopConstraint?.isActive = true
    }

    private func configureProgressCard() {
        progressCard.translatesAutoresizingMaskIntoConstraints = false
        progressCard.layer.cornerRadius = 14
        progressCard.layer.cornerCurve = .continuous
        progressCard.clipsToBounds = true
        progressCard.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.74)
        view.addSubview(progressCard)

        [progressTitleLabel, progressPercentLabel, progressHintLabel, speedLabel, progressView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        progressTitleLabel.font = .systemFont(ofSize: 16, weight: .black)
        progressTitleLabel.textColor = .white
        progressTitleLabel.text = "민원자료 포함 내용"

        progressPercentLabel.font = .systemFont(ofSize: 13, weight: .black)
        progressPercentLabel.textColor = UIColor(red: 0.49, green: 0.95, blue: 0.77, alpha: 1)
        progressPercentLabel.textAlignment = .right
        progressPercentLabel.text = "리포트"

        progressHintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        progressHintLabel.textColor = .white.withAlphaComponent(0.82)
        progressHintLabel.numberOfLines = 0

        speedLabel.font = .systemFont(ofSize: 11, weight: .bold)
        speedLabel.textColor = .white.withAlphaComponent(0.72)
        speedLabel.textAlignment = .right
        speedLabel.text = "GPS/IMU"

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
            progressCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            progressCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            progressTitleLabel.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 14),
            progressTitleLabel.topAnchor.constraint(equalTo: progressContent.topAnchor, constant: 14),

            progressPercentLabel.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -14),
            progressPercentLabel.centerYAnchor.constraint(equalTo: progressTitleLabel.centerYAnchor),

            progressHintLabel.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 14),
            progressHintLabel.topAnchor.constraint(equalTo: progressTitleLabel.bottomAnchor, constant: 8),
            progressHintLabel.trailingAnchor.constraint(equalTo: speedLabel.leadingAnchor, constant: -8),

            speedLabel.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -14),
            speedLabel.centerYAnchor.constraint(equalTo: progressHintLabel.centerYAnchor),
            speedLabel.widthAnchor.constraint(equalToConstant: 70),

            progressView.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 14),
            progressView.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -14),
            progressView.topAnchor.constraint(equalTo: progressHintLabel.bottomAnchor, constant: 10),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            statsStack.leadingAnchor.constraint(equalTo: progressContent.leadingAnchor, constant: 14),
            statsStack.trailingAnchor.constraint(equalTo: progressContent.trailingAnchor, constant: -14),
            statsStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 10),
            statsStack.heightAnchor.constraint(equalToConstant: 72),
            statsStack.bottomAnchor.constraint(equalTo: progressContent.bottomAnchor, constant: -14)
        ])
        progressTopConstraint = progressCard.topAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: 8)
        progressTopConstraint?.isActive = true
    }

    private func configureButtons() {
        let controls = UIStackView(arrangedSubviews: [playButton, resetButton])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.axis = .horizontal
        controls.spacing = 12
        controls.distribution = .fillEqually
        controls.isHidden = true
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

    private func configureEventPanel() {
        eventPanel.translatesAutoresizingMaskIntoConstraints = false
        eventPanel.layer.cornerRadius = 14
        eventPanel.layer.cornerCurve = .continuous
        eventPanel.clipsToBounds = true
        eventPanel.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        view.addSubview(eventPanel)

        eventImageView.translatesAutoresizingMaskIntoConstraints = false
        eventImageView.contentMode = .scaleAspectFill
        eventImageView.clipsToBounds = true
        eventImageView.layer.cornerRadius = 12
        eventImageView.layer.cornerCurve = .continuous

        eventTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        eventTitleLabel.font = .systemFont(ofSize: 15, weight: .black)
        eventTitleLabel.textColor = .white
        eventTitleLabel.numberOfLines = 1

        eventDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        eventDetailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        eventDetailLabel.textColor = .white.withAlphaComponent(0.84)
        eventDetailLabel.numberOfLines = 0

        var videoConfig = UIButton.Configuration.filled()
        videoConfig.baseBackgroundColor = UIColor(red: 0.18, green: 0.33, blue: 0.78, alpha: 0.92)
        videoConfig.baseForegroundColor = .white
        videoConfig.cornerStyle = .medium
        videoConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        videoConfig.attributedTitle = AttributedString("이벤트 클립", attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 12, weight: .black)
        ]))
        eventVideoButton.configuration = videoConfig
        eventVideoButton.addTarget(self, action: #selector(openEventVideo), for: .touchUpInside)

        var actionConfig = UIButton.Configuration.filled()
        actionConfig.baseBackgroundColor = UIColor(red: 1.0, green: 0.43, blue: 0.31, alpha: 0.96)
        actionConfig.baseForegroundColor = .white
        actionConfig.cornerStyle = .medium
        actionConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        actionConfig.attributedTitle = AttributedString("민원 신청", attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 12, weight: .black)
        ]))
        eventActionButton.configuration = actionConfig
        eventActionButton.addTarget(self, action: #selector(openComplaintForSelectedEvent), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [eventTitleLabel, eventDetailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 5
        let actionStack = UIStackView(arrangedSubviews: [eventVideoButton, eventActionButton])
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .horizontal
        actionStack.spacing = 8
        actionStack.distribution = .fillEqually

        let content = eventPanel.contentView
        [eventImageView, textStack, actionStack].forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            eventPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            eventPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            eventPanel.topAnchor.constraint(equalTo: progressCard.bottomAnchor, constant: 10),

            eventImageView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            eventImageView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            eventImageView.widthAnchor.constraint(equalToConstant: 112),
            eventImageView.heightAnchor.constraint(equalToConstant: 82),

            textStack.leadingAnchor.constraint(equalTo: eventImageView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            actionStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            actionStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            actionStack.topAnchor.constraint(equalTo: eventImageView.bottomAnchor, constant: 12),
            actionStack.heightAnchor.constraint(equalToConstant: 40),
            actionStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
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

    private func loadReportHTML() {
        let html = Self.htmlEscapedNonASCII(makeReportHTML())
        if let data = html.data(using: .utf8) {
            webView.load(
                data,
                mimeType: "text/html",
                characterEncodingName: "utf-8",
                baseURL: Self.reportBaseURL
            )
        } else {
            webView.loadHTMLString(html, baseURL: Self.reportBaseURL)
        }
    }

    private func makeReportHTML() -> String {
        let selected = selectedRoute
        let events = replayEvents
        let rows = events.map { event -> String in
            let clip = Self.reportRelativePath(for: Self.eventClipURL(for: event)) ?? ""
            let image = Self.reportRelativePath(for: Self.eventFrameURL(for: event)) ?? ""
            let mediaHTML: String
            if !clip.isEmpty {
                mediaHTML = "<video src=\"\(clip)\" poster=\"\(image)\" controls playsinline muted preload=\"metadata\"></video>"
            } else if !image.isEmpty {
                mediaHTML = "<img src=\"\(image)\" alt=\"event frame\">"
            } else {
                mediaHTML = "<div class=\"media-empty\">이벤트 클립 준비 중</div>"
            }
            return """
            <article class="event-card">
              <div class="media">
                \(mediaHTML)
              </div>
              <div class="event-body">
                <div class="event-kicker">SPOT \(String(format: "%02d", event.index)) · \(event.surfaceLabel)</div>
                <h2>충격 이벤트 클립</h2>
                <dl>
                  <div><dt>GPS 좌표</dt><dd>\(String(format: "%.6f, %.6f", event.coordinate.latitude, event.coordinate.longitude))</dd></div>
                  <div><dt>GPS 정확도</dt><dd>±\(String(format: "%.1f", event.accuracy ?? 0))m</dd></div>
                  <div><dt>속도</dt><dd>\(String(format: "%.1f", event.speedKmh ?? 0))km/h</dd></div>
                  <div><dt>peak</dt><dd>\(String(format: "%.1f", event.peakAcceleration ?? 0))</dd></div>
                  <div><dt>accel RMS</dt><dd>\(String(format: "%.2f", event.accelRMS ?? 0))</dd></div>
                  <div><dt>jerk RMS</dt><dd>\(String(format: "%.1f", event.jerkRMS ?? 0))</dd></div>
                  <div><dt>gyro RMS</dt><dd>\(String(format: "%.2f", event.gyroRMS ?? 0))</dd></div>
                  <div><dt>위험도</dt><dd>노면 \(String(format: "%.0f", event.score))점 · 신뢰도 \(String(format: "%.0f", event.confidence * 100))%</dd></div>
                  <div><dt>판단</dt><dd>\(event.decision)</dd></div>
                </dl>
                <button type="button">민원자료 복붙</button>
              </div>
            </article>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              background: #050606;
              color: #f5f7f5;
              font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif;
              padding: calc(env(safe-area-inset-top) + 22px) 16px calc(env(safe-area-inset-bottom) + 28px);
            }
            header { padding: 10px 2px 18px; border-bottom: 1px solid rgba(255,255,255,.12); }
            .eyebrow { color: #8d9694; font-weight: 900; font-size: 12px; letter-spacing: .04em; }
            h1 { margin: 10px 0 8px; font-size: 32px; line-height: 1.14; }
            .meta { color: #cfd5d2; font-weight: 800; font-size: 16px; line-height: 1.45; }
            .summary {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 10px;
              margin: 16px 0 20px;
            }
            .summary div, .event-card {
              background: #101211;
              border: 1px solid rgba(255,255,255,.09);
              border-radius: 14px;
              box-shadow: 0 10px 28px rgba(0,0,0,.22);
            }
            .summary div { padding: 14px; }
            .summary b { display: block; color: #8d9694; font-size: 12px; margin-bottom: 7px; }
            .summary span { display: block; font-size: 20px; font-weight: 900; line-height: 1.2; }
            .event-card { overflow: hidden; margin: 14px 0; }
            .media { background: #000; }
            video, img { display: block; width: 100%; max-height: 260px; object-fit: cover; background: #000; }
            .media-empty { min-height: 180px; display: grid; place-items: center; color: #9aa3a0; font-weight: 900; background: #0b0d0c; }
            .event-body { padding: 16px; }
            .event-kicker { color: #78f1cf; font-size: 12px; font-weight: 900; margin-bottom: 6px; }
            h2 { margin: 0 0 14px; font-size: 22px; }
            dl { margin: 0; display: grid; gap: 8px; }
            dl div {
              display: grid;
              grid-template-columns: 94px 1fr;
              gap: 10px;
              padding: 8px 0;
              border-bottom: 1px solid rgba(255,255,255,.07);
            }
            dt { color: #aab1ae; font-weight: 800; }
            dd { margin: 0; font-weight: 800; line-height: 1.35; overflow-wrap: anywhere; }
            button {
              width: 100%;
              margin-top: 16px;
              min-height: 48px;
              border: 0;
              border-radius: 9px;
              background: #ff674f;
              color: white;
              font-size: 17px;
              font-weight: 900;
            }
          </style>
        </head>
        <body>
          <header>
            <div class="eyebrow">R2D RIDE REPORT</div>
            <h1>주행 리포트(민원자료)</h1>
            <div class="meta">\(Self.displayName(for: selected)) · \(Self.distanceLabel(for: selected.totalDistance)) · \(Self.durationLabel(for: selected.totalDuration)) · 레드포인트 \(events.count)건</div>
          </header>
          <section class="summary">
            <div><b>문제 레드포인트 GPS 좌표</b><span>SPOT별 위도·경도</span></div>
            <div><b>센서 수집 데이터</b><span>정확도·속도·IMU</span></div>
            <div><b>위험도 판단값</b><span>노면 점수·신뢰도</span></div>
            <div><b>문제좌표 사진·영상</b><span>AI 캡처·이벤트 클립</span></div>
          </section>
          \(rows)
        </body>
        </html>
        """
    }

    private func renderNativeReport() {
        reportStack.arrangedSubviews.forEach { view in
            reportStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let selected = selectedRoute
        let events = replayEvents

        reportStack.addArrangedSubview(reportLabel("R2D RIDE REPORT", size: 13, weight: .black, color: .white.withAlphaComponent(0.55)))
        reportStack.addArrangedSubview(reportLabel("주행 리포트(민원자료)", size: 30, weight: .black, color: .white))
        reportStack.addArrangedSubview(reportLabel("\(Self.displayName(for: selected)) · \(Self.distanceLabel(for: selected.totalDistance)) · \(Self.durationLabel(for: selected.totalDuration)) · 레드포인트 \(events.count)건", size: 16, weight: .bold, color: .white.withAlphaComponent(0.78)))
        reportStack.addArrangedSubview(summaryGrid(events: events))

        if events.isEmpty {
            reportStack.addArrangedSubview(reportCard(title: "감지된 충격 이벤트 없음", body: "이번 주행 경로에서는 민원 후보로 볼 충격 이벤트가 확인되지 않았습니다."))
        } else {
            events.forEach { reportStack.addArrangedSubview(eventCard(for: $0, allEvents: events)) }
        }
    }

    private func summaryGrid(events: [ReplayEvent]) -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10
        let rows = [
            [summaryTile("GPS 좌표", "SPOT \(events.count)건"), summaryTile("센서 데이터", "정확도·속도·IMU")],
            [summaryTile("위험 판단", "점수·신뢰도"), summaryTile("사진·영상", "AI 캡처·이벤트 클립")]
        ]
        rows.forEach { values in
            let row = UIStackView(arrangedSubviews: values)
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            grid.addArrangedSubview(row)
        }
        return grid
    }

    private func summaryTile(_ title: String, _ value: String) -> UIView {
        reportCard(title: title, body: value)
    }

    private func eventCard(for event: ReplayEvent, allEvents: [ReplayEvent]) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 12
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.065, alpha: 1)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        let image = UIImageView(image: Self.imageFromFile(Self.eventFrameURL(for: event)) ?? Self.makeAICaptureImage(for: event, route: selectedRoute))
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 10
        image.heightAnchor.constraint(equalToConstant: 170).isActive = true
        card.addArrangedSubview(image)

        card.addArrangedSubview(reportLabel("SPOT \(String(format: "%02d", event.index)) · \(event.surfaceLabel)", size: 12, weight: .black, color: UIColor(red: 0.49, green: 0.95, blue: 0.77, alpha: 1)))
        card.addArrangedSubview(reportLabel("충격 이벤트 클립", size: 22, weight: .black, color: .white))
        card.addArrangedSubview(reportLabel(Self.eventDetailText(event), size: 13, weight: .semibold, color: .white.withAlphaComponent(0.82), monospaced: true))

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        let clipButton = reportButton("이벤트 클립", color: UIColor(red: 0.19, green: 0.34, blue: 0.78, alpha: 1))
        clipButton.addAction(UIAction { [weak self] _ in self?.presentClip(for: event) }, for: .touchUpInside)
        let complaintButton = reportButton("민원자료 복붙", color: UIColor(red: 1.0, green: 0.40, blue: 0.31, alpha: 1))
        complaintButton.addAction(UIAction { [weak self] _ in self?.presentComplaint(for: event, events: allEvents) }, for: .touchUpInside)
        row.addArrangedSubview(clipButton)
        row.addArrangedSubview(complaintButton)
        card.addArrangedSubview(row)
        return card
    }

    private func reportCard(title: String, body: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.065, alpha: 1)
        stack.layer.cornerRadius = 14
        stack.layer.borderWidth = 1
        stack.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        stack.addArrangedSubview(reportLabel(title, size: 13, weight: .black, color: .white.withAlphaComponent(0.58)))
        stack.addArrangedSubview(reportLabel(body, size: 19, weight: .black, color: .white))
        return stack
    }

    private func reportLabel(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, monospaced: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = monospaced ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func reportButton(_ title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        button.configuration = config
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return button
    }

    private static func eventDetailText(_ event: ReplayEvent) -> String {
        String(
            format: """
            GPS 좌표    %.6f, %.6f
            GPS 정확도  ±%.1fm
            속도        %.1fkm/h
            peak        %.1f
            accel RMS   %.2f
            jerk RMS    %.1f
            gyro RMS    %.2f
            위험도      노면 %.0f점 · 신뢰도 %.0f%%
            판단        %@
            """,
            event.coordinate.latitude,
            event.coordinate.longitude,
            event.accuracy ?? 0,
            event.speedKmh ?? 0,
            event.peakAcceleration ?? 0,
            event.accelRMS ?? 0,
            event.jerkRMS ?? 0,
            event.gyroRMS ?? 0,
            event.score,
            event.confidence * 100,
            event.decision
        )
    }

    private static func imageFromFile(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func presentClip(for event: ReplayEvent) {
        Task { @MainActor in
            let clipURL: URL?
            if let eventClip = Self.eventClipURL(for: event) {
                clipURL = eventClip
            } else {
                clipURL = await Self.exportDemoClip(around: event.time)
            }
            guard let url = clipURL else { return }
            let player = AVPlayer(url: url)
            let controller = AVPlayerViewController()
            controller.player = player
            present(controller, animated: true) { player.play() }
        }
    }

    private func presentComplaint(for event: ReplayEvent, events: [ReplayEvent]) {
        let image = Self.makeAICaptureImage(for: event, route: selectedRoute)
        let description = Self.complaintDescription(selected: event, events: events, route: selectedRoute)
        Task { @MainActor in
            let clipURL: URL?
            if let eventClip = Self.eventClipURL(for: event) {
                clipURL = eventClip
            } else {
                clipURL = await Self.exportDemoClip(around: event.time)
            }
            let controller = RoadComplaintViewController(
                initialCoordinate: event.coordinate,
                initialDescription: description,
                initialImage: image,
                initialVideoURL: clipURL
            )
            present(UINavigationController(rootViewController: controller), animated: true)
        }
    }

    private func updateSelection(index: Int, resetProgress: Bool) {
        guard routes.indices.contains(index) else { return }
        selectedIndex = index
        let selected = selectedRoute
        let events = replayEvents
        routePicker.selectedSegmentIndex = index
        titleLabel.text = "주행 리포트(민원자료)"
        metaLabel.text = "\(Self.displayName(for: selected)) · \(Self.distanceLabel(for: selected.totalDistance)) · \(Self.durationLabel(for: selected.totalDuration)) · 레드포인트 \(events.count)건"
        miniSummaryLabel.text = "\(Self.distanceLabel(for: selected.totalDistance)) · 이벤트 \(events.count)건"
        progressTitleLabel.text = "민원자료 포함 내용"
        progressPercentLabel.text = "리포트"
        speedLabel.text = "GPS/IMU"
        progressHintLabel.text = "SPOT별 좌표, GPS 정확도·속도·IMU 지표, 노면 점수·신뢰도, AI 캡처 후보를 포함합니다."
        routeTypeCard.update(title: "GPS 좌표", value: "SPOT \(events.count)건")
        distanceCard.update(title: "센서 데이터", value: "속도·IMU")
        durationCard.update(title: "위험 판단", value: "점수·신뢰도")
        updateEventPanel(events: events)

        if resetProgress {
            currentStep = 0
            updateProgress(step: 0)
        }
        if autoPlay {
            playReplay()
        }
    }

    private func updateEventPanel(events: [ReplayEvent]) {
        guard let event = events.first else {
            eventPanel.isHidden = false
            eventImageView.image = Self.makeEmptyCaptureImage(route: selectedRoute)
            eventTitleLabel.text = "감지된 충격 이벤트 없음"
            eventDetailLabel.text = "이번 주행 경로에서는 민원 후보로 볼 충격 이벤트가 확인되지 않았습니다.\n경로와 주행 기록만 리포트로 저장됩니다."
            eventVideoButton.isEnabled = false
            eventVideoButton.alpha = 0.45
            eventActionButton.isEnabled = false
            eventActionButton.alpha = 0.45
            return
        }
        eventPanel.isHidden = false
        eventVideoButton.isEnabled = Self.eventClipURL(for: event) != nil || Self.demoVideoURL() != nil
        eventVideoButton.alpha = eventVideoButton.isEnabled ? 1 : 0.45
        eventActionButton.isEnabled = true
        eventActionButton.alpha = 1
        eventImageView.image = Self.makeAICaptureImage(for: event, route: selectedRoute)
        eventTitleLabel.text = "대표 레드포인트 · 민원 신청"
        eventDetailLabel.text = String(
            format: "좌표 %.6f, %.6f · GPS ±%.1fm\n속도 %.1fkm/h · peak %.1f · accel %.2f · jerk %.1f · gyro %.2f\n노면 %.0f점 · 신뢰도 %.0f%% · %@\n영상: SPOT %02d 충격 이벤트 클립",
            event.coordinate.latitude,
            event.coordinate.longitude,
            event.accuracy ?? 0,
            event.speedKmh ?? 0,
            event.peakAcceleration ?? event.score,
            event.accelRMS ?? 0,
            event.jerkRMS ?? 0,
            event.gyroRMS ?? 0,
            event.score,
            event.confidence * 100,
            event.decision,
            event.index
        )
    }

    private func updateProgress(step: Int) {
        let selected = selectedRoute
        let maxStep = max(totalSteps, 1)
        let ratio = min(1, max(0, Float(step) / Float(maxStep)))
        let remainingDistance = selected.totalDistance * Double(1 - ratio)
        let remainingDuration = selected.totalDuration * Double(1 - ratio)
        progressView.setProgress(ratio, animated: true)
        progressPercentLabel.text = "\(Int((ratio * 100).rounded()))%"
        progressTitleLabel.text = ratio > 0 ? "리플레이 진행 중" : "민원자료 포함 내용"
        statePill.text = ratio == 0 ? "민원자료" : (ratio >= 1 ? "완료" : "재생 중")
        speedLabel.text = ratio > 0 ? "남은 \(String(format: "%.1f", remainingDistance / 1000))km" : "GPS/IMU"
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

    @objc private func openComplaintForSelectedEvent() {
        let events = replayEvents
        guard let event = events.first else { return }
        let image = Self.makeAICaptureImage(for: event, route: selectedRoute)
        let description = Self.complaintDescription(selected: event, events: events, route: selectedRoute)
        Task { @MainActor in
            let clipURL: URL?
            if let eventClip = Self.eventClipURL(for: event) {
                clipURL = eventClip
            } else {
                clipURL = await Self.exportDemoClip(around: event.time)
            }
            let controller = RoadComplaintViewController(
                initialCoordinate: event.coordinate,
                initialDescription: description,
                initialImage: image,
                initialVideoURL: clipURL ?? Self.demoVideoURL()
            )
            let navigation = UINavigationController(rootViewController: controller)
            present(navigation, animated: true)
        }
    }

    @objc private func openEventVideo() {
        let events = replayEvents
        guard let event = events.first else { return }
        Task { @MainActor in
            let clipURL: URL?
            if let eventClip = Self.eventClipURL(for: event) {
                clipURL = eventClip
            } else {
                clipURL = await Self.exportDemoClip(around: event.time)
            }
            guard let url = clipURL else { return }
            let player = AVPlayer(url: url)
            let controller = AVPlayerViewController()
            controller.player = player
            present(controller, animated: true) {
                player.play()
            }
        }
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
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] timer in
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
              background: #071716;
              font-family: "Apple SD Gothic Neo", "Noto Sans CJK KR", -apple-system, BlinkMacSystemFont, sans-serif;
            }
            #map canvas {
              outline: none;
            }
            .maplibregl-ctrl-top-right,
            .maplibregl-ctrl-top-left { margin-top: 110px; }
            .maplibregl-ctrl-bottom-left,
            .maplibregl-ctrl-bottom-right { margin-bottom: 150px; }
            .maplibregl-ctrl-attrib { color: #2d4a45; font-size: 10px; }
          </style>
        </head>
        <body>
          <div id="map"></div>
          <script>
            const data = \(payload);
            const {MapboxOverlay, PathLayer, ScatterplotLayer} = deck;
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
                    maxzoom: 19,
                    attribution: '© OpenStreetMap contributors'
                  },
                  satellite: {
                    type: 'raster',
                    tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
                    tileSize: 256,
                    maxzoom: 19,
                    attribution: 'Imagery © Esri, Maxar, Earthstar Geographics'
                  }
                },
                layers: [
                  {
                    id: 'satellite',
                    type: 'raster',
                    source: 'satellite',
                    paint: {
                      'raster-saturation': -0.12,
                      'raster-contrast': 0.06,
                      'raster-brightness-max': 0.92
                    }
                  }
                ]
              },
              center: coords[0],
              zoom: 15.8,
              pitch: 0,
              bearing: 0,
              attributionControl: true
            });

            function layersForCurrentState() {
              const pathLayer = new PathLayer({
                id: 'selected-route',
                data: [{path: selected.coordinates}],
                getPath: d => d.path,
                getColor: [39, 215, 173, 245],
                getWidth: 7,
                widthMinPixels: 7,
                capRounded: true,
                jointRounded: true
              });

              const eventLayer = new ScatterplotLayer({
                id: 'replay-events',
                data: selected.events || [],
                getPosition: d => d.position,
                getRadius: d => d.score <= 45 ? 12 : 10,
                radiusUnits: 'pixels',
                radiusMinPixels: 10,
                radiusMaxPixels: 14,
                getFillColor: [255, 45, 72, 235],
                getLineColor: [255, 255, 255, 235],
                lineWidthMinPixels: 3,
                stroked: true,
                filled: true,
                pickable: true
              });

              return [pathLayer, eventLayer];
            }

            function cameraFor(index) {
              const current = coords[Math.min(index, coords.length - 1)];
              const next = coords[Math.min(index + 8, coords.length - 1)];
              const bearing = turfBearing(current, next);
              return { center: current, bearing };
            }

            function fitToSelectedRoute(duration) {
              const bounds = coords.reduce((b, c) => b.extend(c), new maplibregl.LngLatBounds(coords[0], coords[0]));
              map.fitBounds(bounds, { padding: {top: 98, right: 36, bottom: 170, left: 36}, maxZoom: 17.2, pitch: 0, bearing: 0, duration });
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
            });

            window.selectRoute = function selectRoute(routeID) {
              selectedRouteID = routeID;
              selected = data.routes.find(r => r.id === selectedRouteID) || data.routes[0];
              coords = selected.coordinates;
              refreshOverlay();
              fitToSelectedRoute(700);
            }

            window.resetReplay = function resetReplay() {
              cancelAnimationFrame(animationFrame);
              refreshOverlay();
              fitToSelectedRoute(700);
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
        let route = selectedRoute
        let routePayloads = [
            [
                "id": route.id,
                "name": Self.displayName(for: route),
                "subtitle": Self.subtitle(for: route),
                "distance": route.totalDistance,
                "duration": route.totalDuration,
                "coordinates": route.polyline.map { [$0.longitude, $0.latitude] },
                "events": Self.events(from: route).map { event in
                    [
                        "id": event.id,
                        "position": [event.coordinate.longitude, event.coordinate.latitude],
                        "score": event.score,
                        "confidence": event.confidence
                    ] as [String: Any]
                }
            ] as [String: Any]
        ]
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
        case "pm", "pm_time_priority": return "최소시간"
        case "pm_main_road": return "큰길 위주"
        case "pm_short_distance_priority": return "최단거리"
        default: return route.providerOption ?? "선택 경로"
        }
    }

    private static func subtitle(for route: Route) -> String {
        switch route.providerOption {
        case "pm", "pm_time_priority": return "최소시간 경로"
        case "pm_main_road": return "큰길 위주 경로"
        case "pm_short_distance_priority": return "최단거리 경로"
        default: return "선택한 경로"
        }
    }

    private static func durationLabel(for duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes)분"
    }

    private static func distanceLabel(for distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1fkm", distance / 1000)
        }
        return "\(Int(distance.rounded()))m"
    }

    private static var reportBaseURL: URL {
        URL(fileURLWithPath: "/Users/seulbinlee/R2D/", isDirectory: true)
    }

    private static func reportRelativePath(for url: URL?) -> String? {
        guard let url else { return nil }
        let basePath = reportBaseURL.path
        guard url.path.hasPrefix(basePath) else { return url.absoluteString }
        return String(url.path.dropFirst(basePath.count)).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    private static func htmlEscapedNonASCII(_ html: String) -> String {
        html.unicodeScalars.map { scalar in
            scalar.isASCII ? String(scalar) : "&#\(scalar.value);"
        }.joined()
    }

    private static func demoVideoURL() -> URL? {
        let attached = URL(fileURLWithPath: "/Users/seulbinlee/Downloads/1786278944600.mp4")
        if FileManager.default.fileExists(atPath: attached.path) {
            return attached
        }
        return Bundle.main.url(forResource: "event-clip", withExtension: "mp4")
    }

    private static func eventClipURL(for event: ReplayEvent) -> URL? {
        let fileManager = FileManager.default
        let paddedName = String(format: "event-%02d.mp4", event.index)
        let plainName = "event-\(event.index)-slow.mp4"
        let candidates = [
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/public/latest-capture/events/\(paddedName)"),
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/processed/dongtan-latest/events/\(paddedName)"),
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/public/event-clips/\(plainName)"),
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/media/jamwon/event-clips/\(plainName)")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func eventFrameURL(for event: ReplayEvent) -> URL? {
        let fileManager = FileManager.default
        let paddedName = String(format: "event-%02d.jpg", event.index)
        let plainName = "event-\(event.index).jpg"
        let candidates = [
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/public/latest-capture/events/\(paddedName)"),
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/processed/dongtan-latest/events/\(paddedName)"),
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/public/event-frames/\(plainName)"),
            URL(fileURLWithPath: "/Users/seulbinlee/R2D/R2D_Web/media/jamwon/event-frames/\(plainName)")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func exportDemoClip(around eventTime: Double?) async -> URL? {
        guard let source = demoVideoURL() else { return nil }
        let startSeconds = max(0, (eventTime ?? 1.5) - 1.5)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("r2d-event-clip-\(Int(startSeconds * 1000)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return source
        }
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: 3, preferredTimescale: 600)
        )

        return await withCheckedContinuation { continuation in
            export.exportAsynchronously {
                if export.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(returning: source)
                }
            }
        }
    }

    private static func events(from route: Route) -> [ReplayEvent] {
        let bundledEvents = bundledSensorEvents()
        return route.riskCells.enumerated()
            .compactMap { index, cell -> ReplayEvent? in
                guard let coordinate = coordinate(from: cell.geometry) else { return nil }
                let bundled = bundledEvents[cell.id] ?? bundledEvents[String(cell.id.split(separator: "-").last ?? "")]
                return ReplayEvent(
                    id: cell.id,
                    coordinate: coordinate,
                    score: cell.riskScore,
                    confidence: cell.confidence,
                    index: index + 1,
                    time: bundled?.time,
                    accuracy: bundled?.accuracy,
                    speedKmh: bundled?.speedKmh,
                    peakAcceleration: bundled?.peakAcceleration,
                    accelRMS: bundled?.accelRMS,
                    jerkRMS: bundled?.jerkRMS,
                    gyroRMS: bundled?.gyroRMS,
                    decision: bundled?.decision ?? "충격 이벤트 후보",
                    surfaceLabel: bundled?.surfaceLabel ?? "노면 이상 후보",
                    evidenceSource: bundled?.videoSource
                )
            }
            .sorted { $0.score < $1.score }
    }

    private struct BundledSensorEvent {
        let time: Double
        let accuracy: Double
        let speedKmh: Double
        let peakAcceleration: Double
        let accelRMS: Double
        let jerkRMS: Double
        let gyroRMS: Double
        let decision: String
        let surfaceLabel: String
        let videoSource: String
    }

    private static func bundledSensorEvents() -> [String: BundledSensorEvent] {
        guard let data = try? DemoResourceBundle.data(named: "sensor-2026-08-09-events.csv"),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        return simpleCSVRows(text).reduce(into: [:]) { result, row in
            guard let id = row["id"] else { return }
            let event = BundledSensorEvent(
                time: Double(row["time"] ?? "") ?? 0,
                accuracy: Double(row["accuracy"] ?? "") ?? 0,
                speedKmh: Double(row["speedKmh"] ?? "") ?? 0,
                peakAcceleration: Double(row["peakAcceleration"] ?? "") ?? 0,
                accelRMS: Double(row["accelRms"] ?? "") ?? 0,
                jerkRMS: Double(row["jerkRms"] ?? "") ?? 0,
                gyroRMS: Double(row["gyroRms"] ?? "") ?? 0,
                decision: row["decision"]?.isEmpty == false ? row["decision"]! : "충격 이벤트 후보",
                surfaceLabel: row["surfaceLabel"]?.isEmpty == false ? row["surfaceLabel"]! : "노면 이상 후보",
                videoSource: row["videoSource"] ?? ""
            )
            result[id] = event
            result["sensor-2026-08-09-event-\(id)"] = event
        }
    }

    private static func simpleCSVRows(_ text: String) -> [[String: String]] {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { splitCSVLine(String($0)) }
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { values in
            Dictionary(uniqueKeysWithValues: header.enumerated().map { index, key in
                (key, index < values.count ? values[index] : "")
            })
        }
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        values.append(current)
        return values
    }

    private static func complaintDescription(selected: ReplayEvent, events: [ReplayEvent], route: Route) -> String {
        let coordinateLines = events.map { event in
            String(
                format: "  - SPOT %02d: %.6f, %.6f%@",
                event.index,
                event.coordinate.latitude,
                event.coordinate.longitude,
                event.accuracy.map { String(format: " / GPS 오차 ±%.1fm", $0) } ?? ""
            )
        }.joined(separator: "\n")
        let sensorLines = events.map { event in
            String(
                format: "  - SPOT %02d: peak %.1fm/s², accel RMS %.2f, jerk RMS %.1f, gyro RMS %.2f, 점수 %.0f, 신뢰도 %.0f%%, 판단 %@",
                event.index,
                event.peakAcceleration ?? event.score,
                event.accelRMS ?? 0,
                event.jerkRMS ?? 0,
                event.gyroRMS ?? 0,
                event.score,
                event.confidence * 100,
                event.decision
            )
        }.joined(separator: "\n")
        let photoLines = events.map { event in
            let capture = event.index == selected.index ? "앱 AI 캡처 사진 첨부됨" : "앱 AI 캡처 후보"
            let source = event.evidenceSource?.isEmpty == false ? " / 원본 \(event.evidenceSource!)" : ""
            return String(format: "  - SPOT %02d: %@%@ / %@", event.index, capture, source, event.surfaceLabel)
        }.joined(separator: "\n")
        let selectedTime = selected.time.map { String(format: " / 주행 %.0f초", $0) } ?? ""
        return """
        R2D 앱 주행 종료 리포트에서 감지된 위험 레드포인트 현장 확인 요청입니다.

        1. 대표 문제 좌표
        - SPOT \(String(format: "%02d", selected.index)): \(String(format: "%.6f, %.6f", selected.coordinate.latitude, selected.coordinate.longitude))\(selectedTime)
        - 노면 점수 \(String(format: "%.0f", selected.score))점, 신뢰도 \(String(format: "%.0f", selected.confidence * 100))%

        2. 문제 레드포인트 GPS 좌표
        \(coordinateLines)

        3. 센서로 수집한 데이터
        - 경로: \(displayName(for: route)) / 총 거리 \(String(format: "%.2f", route.totalDistance / 1000))km / 예상 시간 \(durationLabel(for: route.totalDuration))
        - 수집 항목: GPS 좌표, GPS 정확도, 속도, 가속도 peak, accel RMS, jerk RMS, gyro RMS, 상대 노면점수, 신뢰도
        \(sensorLines)

        4. 문제좌표 사진들
        \(photoLines)

        파손 확정 판정이 아니라 스마트폰 GPS·IMU·앱 캡처 기반의 현장 확인 요청 건입니다. 공식 민원 제출 시 앱에 표시된 문제좌표 캡처 사진을 함께 첨부해 주세요.
        """
    }

    private static func coordinate(from geometry: String) -> Coordinate? {
        let trimmed = geometry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("POINT") else { return nil }
        let values = trimmed
            .replacingOccurrences(of: "POINT", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard values.count >= 2 else { return nil }
        return Coordinate(latitude: values[1], longitude: values[0])
    }

    private static func makeAICaptureImage(for event: ReplayEvent, route: Route) -> UIImage {
        let size = CGSize(width: 640, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.035, green: 0.07, blue: 0.09, alpha: 1).setFill()
            context.fill(rect)

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.05, green: 0.52, blue: 0.48, alpha: 1).cgColor,
                    UIColor(red: 1.00, green: 0.24, blue: 0.29, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            UIColor.black.withAlphaComponent(0.24).setFill()
            context.fill(rect)

            let pathRect = CGRect(x: 70, y: 120, width: 500, height: 130)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: pathRect.minX, y: pathRect.midY + 32))
            path.addCurve(
                to: CGPoint(x: pathRect.maxX, y: pathRect.midY - 18),
                controlPoint1: CGPoint(x: pathRect.minX + 130, y: pathRect.minY - 20),
                controlPoint2: CGPoint(x: pathRect.maxX - 180, y: pathRect.maxY + 60)
            )
            UIColor.white.withAlphaComponent(0.26).setStroke()
            path.lineWidth = 24
            path.lineCapStyle = .round
            path.stroke()
            UIColor(red: 0.19, green: 0.84, blue: 0.63, alpha: 1).setStroke()
            path.lineWidth = 12
            path.stroke()

            let eventPoint = CGPoint(x: pathRect.maxX - 135, y: pathRect.midY - 4)
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: eventPoint.x - 36, y: eventPoint.y - 36, width: 72, height: 72)).fill()
            UIColor(red: 1.0, green: 0.19, blue: 0.26, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: eventPoint.x - 23, y: eventPoint.y - 23, width: 46, height: 46)).fill()

            let title = "AI 민원 캡처 후보"
            title.draw(
                at: CGPoint(x: 42, y: 38),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .black),
                    .foregroundColor: UIColor.white
                ]
            )
            let subtitle = String(format: "이벤트 #%02d · 노면 점수 %.0f · 신뢰도 %.0f%%", event.index, event.score, event.confidence * 100)
            subtitle.draw(
                at: CGPoint(x: 44, y: 82),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.86)
                ]
            )
            let footer = String(format: "%.6f, %.6f · %@", event.coordinate.latitude, event.coordinate.longitude, displayName(for: route))
            footer.draw(
                at: CGPoint(x: 44, y: 350),
                withAttributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.82)
                ]
            )
        }
    }

    private static func makeEmptyCaptureImage(route: Route) -> UIImage {
        let size = CGSize(width: 640, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.04, green: 0.08, blue: 0.10, alpha: 1).setFill()
            context.fill(rect)
            UIColor(red: 0.19, green: 0.84, blue: 0.63, alpha: 1).withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: CGRect(x: 44, y: 44, width: 552, height: 332), cornerRadius: 28).fill()
            let title = "이벤트 없음"
            title.draw(
                at: CGPoint(x: 64, y: 64),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .black),
                    .foregroundColor: UIColor.white
                ]
            )
            let subtitle = String(format: "%@ · %.1fkm", displayName(for: route), route.totalDistance / 1000)
            subtitle.draw(
                at: CGPoint(x: 66, y: 116),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.80)
                ]
            )
        }
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

    func update(title: String? = nil, value: String) {
        if let title {
            titleLabel.text = title
        }
        valueLabel.text = value
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

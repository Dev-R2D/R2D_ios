#if canImport(UIKit)
import CoreLocation
import R2DCore
import SafariServices
import UIKit

public final class RoadComplaintViewController: UIViewController {
    private static let complaintURL = URL(string: "https://www.epeople.go.kr/index.jsp")!
    private let defectTypes = ["탈락", "단차", "파손", "포트홀", "마모", "줄눈벌어짐", "융기", "배수시설", "점자블록", "시설물커버", "판단불가"]

    private let initialCoordinate: Coordinate?
    private let initialDescription: String?
    private let initialImage: UIImage?
    private let initialVideoURL: URL?
    private let locationManager = CLLocationManager()
    private var selectedCoordinate: Coordinate?
    private var selectedImage: UIImage?
    private var currentStep = 1
    private var selectedTypeIndex = 2
    private var typeButtons: [UIButton] = []

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let stepStack = UIStackView()
    private let stepLabels = [UILabel(), UILabel(), UILabel()]
    private let locationStep = UIStackView()
    private let typeStep = UIStackView()
    private let confirmStep = UIStackView()
    private let locationField = UITextField()
    private let descriptionView = UITextView()
    private let photoButton = UIButton(type: .system)
    private let photoPreview = UIImageView()
    private let confirmLabel = UILabel()
    private let submitButton = UIButton(type: .system)

    public init(initialCoordinate: Coordinate?, initialDescription: String? = nil, initialImage: UIImage? = nil, initialVideoURL: URL? = nil) {
        self.initialCoordinate = initialCoordinate
        self.initialDescription = initialDescription
        self.initialImage = initialImage
        self.initialVideoURL = initialVideoURL
        selectedCoordinate = initialCoordinate
        selectedImage = initialImage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "도로 민원 신고"
        view.backgroundColor = UIColor(red: 0.035, green: 0.07, blue: 0.09, alpha: 1)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "닫기", style: .plain, target: self, action: #selector(close))
        locationManager.delegate = self
        configureLayout()
        showStep(1)
    }

    private func configureLayout() {
        view.backgroundColor = UIColor(red: 0.98, green: 0.985, blue: 0.97, alpha: 1)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 28
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -22),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        ])

        configureHwaseongComplaintForm()
    }

    private func configureHwaseongComplaintForm() {
        stepStack.isHidden = true
        contentStack.addArrangedSubview(formTitle("신청인 기본정보"))
        contentStack.addArrangedSubview(formRow(label: "작성자", value: "홍길동"))
        contentStack.addArrangedSubview(formRow(label: "성별", value: "남성    연령  23세"))
        contentStack.addArrangedSubview(formRow(label: "* 전화번호", value: "010 - 1234 - 5678"))
        contentStack.addArrangedSubview(formRow(label: "* 이메일주소", value: "R2D1234 @ naver.com"))
        if let initialCoordinate {
            locationField.text = coordinateText(initialCoordinate)
        }
        contentStack.addArrangedSubview(formInputRow(label: "* 주소", field: locationField, placeholder: "GPS 좌표 또는 기본주소"))

        contentStack.addArrangedSubview(formTitle("소통의견 입력정보"))
        let titleField = UITextField()
        titleField.borderStyle = .roundedRect
        titleField.backgroundColor = .white
        titleField.textColor = .black
        titleField.text = "R2D 주행 중 감지된 도로 파손 의심 구간 현장 확인 요청"
        contentStack.addArrangedSubview(formInputRow(label: "* 제목", field: titleField, placeholder: "제목"))
        contentStack.addArrangedSubview(formRow(label: "* 관련분야", value: "교통·도로        * 지역명  화성시"))

        descriptionView.heightAnchor.constraint(equalToConstant: 260).isActive = true
        descriptionView.layer.borderColor = UIColor(white: 0.84, alpha: 1).cgColor
        descriptionView.layer.borderWidth = 1
        descriptionView.backgroundColor = .white
        descriptionView.textColor = .black
        descriptionView.font = .systemFont(ofSize: 14)
        descriptionView.text = initialDescription ?? "도로 파손 의심 구간입니다. 현장 확인 및 조치 요청드립니다."
        contentStack.addArrangedSubview(formTextRow(label: "* 내용", textView: descriptionView))

        contentStack.addArrangedSubview(formTitle("개인정보 수집 및 이용안내 동의"))
        contentStack.addArrangedSubview(formRow(label: "* 동의여부", value: "☑ 위의 개인정보 수집 정책에 동의합니다."))
        contentStack.addArrangedSubview(formRow(label: "* 컨텐츠관련", value: "☑ 소통종결되어 답변되지 않음에 동의합니다."))

        configureButton(submitButton, title: "복붙", color: .systemBlue, action: #selector(submitComplaint))
        contentStack.addArrangedSubview(submitButton)
    }

    private func configureSteps() {
        stepStack.axis = .horizontal
        stepStack.spacing = 8
        stepStack.distribution = .fillEqually
        let titles = ["1. 위치 선택", "2. 신고유형", "3. 확인·민원접수"]
        for index in stepLabels.indices {
            let label = stepLabels[index]
            label.text = titles[index]
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13, weight: .bold)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.heightAnchor.constraint(equalToConstant: 36).isActive = true
            stepStack.addArrangedSubview(label)
        }
        contentStack.addArrangedSubview(stepStack)
    }

    private func configureLocationStep() {
        setupStepStack(locationStep)
        locationStep.addArrangedSubview(sectionTitle("현재 위치 또는 위치 검색 후 선택"))
        let currentButton = UIButton(type: .system)
        configureButton(currentButton, title: "현재 위치로 신고하기", color: .systemBlue, action: #selector(useCurrentLocation))
        locationStep.addArrangedSubview(currentButton)

        locationField.borderStyle = .roundedRect
        locationField.backgroundColor = .white
        locationField.textColor = .black
        locationField.placeholder = "주소 또는 GPS 좌표 입력"
        if let initialCoordinate {
            locationField.text = coordinateText(initialCoordinate)
        }
        locationStep.addArrangedSubview(locationField)

        let selectButton = UIButton(type: .system)
        configureButton(selectButton, title: "입력한 위치 선택", color: .systemTeal, action: #selector(selectTypedLocation))
        locationStep.addArrangedSubview(selectButton)

        let nextButton = UIButton(type: .system)
        configureButton(nextButton, title: "다음", color: .systemIndigo, action: #selector(goTypeStep))
        locationStep.addArrangedSubview(nextButton)
        contentStack.addArrangedSubview(locationStep)
    }

    private func configureTypeStep() {
        setupStepStack(typeStep)
        typeStep.addArrangedSubview(sectionTitle("신고유형"))

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10
        for rowStart in stride(from: 0, to: defectTypes.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            for index in rowStart..<min(rowStart + 2, defectTypes.count) {
                let button = typeButton(title: defectTypes[index], index: index)
                typeButtons.append(button)
                row.addArrangedSubview(button)
            }
            grid.addArrangedSubview(row)
        }
        typeStep.addArrangedSubview(grid)
        updateTypeButtons()

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        let back = UIButton(type: .system)
        configureButton(back, title: "이전", color: .systemGray, action: #selector(goLocationStep))
        let next = UIButton(type: .system)
        configureButton(next, title: "다음", color: .systemIndigo, action: #selector(goConfirmStep))
        row.addArrangedSubview(back)
        row.addArrangedSubview(next)
        typeStep.addArrangedSubview(row)
        contentStack.addArrangedSubview(typeStep)
    }

    private func configureConfirmStep() {
        setupStepStack(confirmStep)
        confirmStep.addArrangedSubview(sectionTitle("확인·민원접수"))
        confirmLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        confirmLabel.textColor = .white.withAlphaComponent(0.84)
        confirmLabel.numberOfLines = 0
        confirmStep.addArrangedSubview(confirmLabel)

        confirmStep.addArrangedSubview(sectionTitle("추가 설명"))
        descriptionView.heightAnchor.constraint(equalToConstant: 140).isActive = true
        descriptionView.layer.cornerRadius = 10
        descriptionView.backgroundColor = .white
        descriptionView.textColor = .black
        descriptionView.font = .systemFont(ofSize: 16)
        descriptionView.text = initialDescription ?? "도로 파손 의심 구간입니다. 현장 확인 및 조치 요청드립니다."
        confirmStep.addArrangedSubview(descriptionView)

        configureButton(photoButton, title: "사진 첨부", color: .systemBlue, action: #selector(choosePhoto))
        confirmStep.addArrangedSubview(photoButton)
        photoPreview.contentMode = .scaleAspectFill
        photoPreview.clipsToBounds = true
        photoPreview.layer.cornerRadius = 10
        photoPreview.heightAnchor.constraint(equalToConstant: 180).isActive = true
        photoPreview.image = initialImage
        photoPreview.isHidden = initialImage == nil
        confirmStep.addArrangedSubview(photoPreview)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        let back = UIButton(type: .system)
        configureButton(back, title: "이전", color: .systemGray, action: #selector(goTypeStep))
        configureButton(submitButton, title: "민원 접수창 열기", color: .systemOrange, action: #selector(submitComplaint))
        row.addArrangedSubview(back)
        row.addArrangedSubview(submitButton)
        confirmStep.addArrangedSubview(row)
        contentStack.addArrangedSubview(confirmStep)
    }

    private func setupStepStack(_ stack: UIStackView) {
        stack.axis = .vertical
        stack.spacing = 12
    }

    private func formTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 24, weight: .black)
        label.textColor = UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
        label.numberOfLines = 0
        return label
    }

    private func formRow(label: String, value: String) -> UIView {
        let labelView = formLabel(label)
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 15, weight: .medium)
        valueLabel.textColor = UIColor(white: 0.28, alpha: 1)
        valueLabel.numberOfLines = 0
        return formContainer(labelView: labelView, content: valueLabel, height: 54)
    }

    private func formInputRow(label: String, field: UITextField, placeholder: String) -> UIView {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.backgroundColor = .white
        field.textColor = .black
        field.font = .systemFont(ofSize: 15)
        return formContainer(labelView: formLabel(label), content: field, height: 62)
    }

    private func formTextRow(label: String, textView: UITextView) -> UIView {
        formContainer(labelView: formLabel(label), content: textView, height: 290)
    }

    private func formLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .black)
        label.textColor = text.hasPrefix("*") ? .systemRed : UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func formContainer(labelView: UIView, content: UIView, height: CGFloat) -> UIView {
        let row = UIStackView(arrangedSubviews: [labelView, content])
        row.axis = .horizontal
        row.spacing = 0
        row.alignment = .fill
        row.distribution = .fill
        row.layer.borderColor = UIColor(white: 0.84, alpha: 1).cgColor
        row.layer.borderWidth = 1
        row.backgroundColor = .white
        labelView.backgroundColor = UIColor(white: 0.96, alpha: 1)
        labelView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
        if let stackContent = content as? UIStackView {
            stackContent.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
            stackContent.isLayoutMarginsRelativeArrangement = true
        } else {
            content.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        }
        return row
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .white
        label.numberOfLines = 0
        return label
    }

    private func configureButton(_ button: UIButton, title: String, color: UIColor, action: Selector) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        button.configuration = config
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func typeButton(title: String, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 2
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        button.addTarget(self, action: #selector(selectComplaintType(_:)), for: .touchUpInside)
        return button
    }

    private func updateTypeButtons() {
        for button in typeButtons {
            var config = UIButton.Configuration.filled()
            config.title = defectTypes[button.tag]
            config.baseForegroundColor = .white
            config.baseBackgroundColor = button.tag == selectedTypeIndex ? .systemIndigo : .white.withAlphaComponent(0.14)
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
            button.configuration = config
            button.layer.borderWidth = button.tag == selectedTypeIndex ? 1.5 : 1
            button.layer.borderColor = (button.tag == selectedTypeIndex ? UIColor.white.withAlphaComponent(0.7) : UIColor.white.withAlphaComponent(0.18)).cgColor
            button.layer.cornerRadius = 10
        }
    }

    private func showStep(_ step: Int) {
        currentStep = step
        locationStep.isHidden = step != 1
        typeStep.isHidden = step != 2
        confirmStep.isHidden = step != 3
        for (index, label) in stepLabels.enumerated() {
            let value = index + 1
            label.backgroundColor = value == step ? .systemIndigo : (value < step ? .systemGreen : .white.withAlphaComponent(0.12))
            label.textColor = .white
        }
        if step == 3 {
            updateConfirmText()
        }
    }

    private func updateConfirmText() {
        confirmLabel.text = """
        위치: \(locationField.text?.isEmpty == false ? locationField.text! : "위치 확인 필요")
        신고유형: \(selectedType)
        """
    }

    private var selectedType: String {
        defectTypes[max(0, min(selectedTypeIndex, defectTypes.count - 1))]
    }

    private var complaintText: String {
        let location = locationField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = descriptionView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        신고유형: \(selectedType)
        위치: \(location.isEmpty ? "현 위치 확인 필요" : location)
        추가 설명: \(description)
        사진 첨부: \(selectedImage == nil ? "없음" : "있음")
        영상 첨부 후보: \(initialVideoURL == nil ? "없음" : "충격 이벤트 2~3초 클립")
        """
    }

    @objc private func useCurrentLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            showAlert(title: "위치 권한 필요", message: "설정에서 위치 권한을 허용하거나 위치를 직접 입력해 주세요.")
        }
    }

    @objc private func selectComplaintType(_ sender: UIButton) {
        selectedTypeIndex = sender.tag
        updateTypeButtons()
    }

    @objc private func selectTypedLocation() {
        selectedCoordinate = coordinateFromLocationField()
        if locationField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            showAlert(title: "위치 입력 필요", message: "주소 또는 GPS 좌표를 입력해 주세요.")
            return
        }
        showAlert(title: "위치 선택 완료", message: locationField.text ?? "")
    }

    @objc private func goLocationStep() { showStep(1) }
    @objc private func goTypeStep() {
        if currentStep == 1, locationField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            showAlert(title: "위치 선택 필요", message: "현재 위치를 사용하거나 주소/GPS 좌표를 입력해 주세요.")
            return
        }
        showStep(2)
    }
    @objc private func goConfirmStep() { showStep(3) }

    @objc private func choosePhoto() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true
        let sheet = UIAlertController(title: "사진 첨부", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "카메라 촬영", style: .default) { [weak self] _ in
                picker.sourceType = .camera
                self?.present(picker, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "앨범에서 선택", style: .default) { [weak self] _ in
            picker.sourceType = .photoLibrary
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func submitComplaint() {
        UIPasteboard.general.string = complaintText
        showCopiedNotice()
    }

    private func coordinateFromLocationField() -> Coordinate? {
        guard let text = locationField.text else { return nil }
        let values = text
            .replacingOccurrences(of: "GPS", with: "")
            .split { $0 == "," || $0 == " " }
            .compactMap { Double($0) }
        guard values.count >= 2 else { return nil }
        return Coordinate(latitude: values[0], longitude: values[1])
    }

    private func coordinateText(_ coordinate: Coordinate) -> String {
        String(format: "GPS %.7f, %.7f (%@)", coordinate.latitude, coordinate.longitude, roadAddressText(for: coordinate))
    }

    private func roadAddressText(for coordinate: Coordinate) -> String {
        if coordinate.latitude >= 37.17, coordinate.latitude <= 37.21,
           coordinate.longitude >= 127.09, coordinate.longitude <= 127.11 {
            return "경기도 화성시 동탄원천로 일대"
        }
        return "경기도 화성시 관내 도로구간"
    }

    private static func timeText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func showCopiedNotice() {
        let alert = UIAlertController(title: "복붙 준비 완료", message: "신고 내용이 클립보드에 복사되어 있습니다. 국민신문고에서 내용을 붙여넣어 최종 제출해 주세요.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "국민신문고 열기", style: .default) { [weak self] _ in
            self?.present(SFSafariViewController(url: Self.complaintURL), animated: true)
        })
        alert.addAction(UIAlertAction(title: "닫기", style: .cancel))
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension RoadComplaintViewController: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        selectedCoordinate = coordinate
        locationField.text = coordinateText(coordinate)
        showAlert(title: "현재 위치 선택 완료", message: coordinateText(coordinate))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        showAlert(title: "현재 위치 확인 실패", message: "주소 또는 GPS 좌표를 직접 입력해 주세요.")
    }
}

extension RoadComplaintViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
        selectedImage = image
        photoPreview.image = image
        photoPreview.isHidden = image == nil
        photoButton.configuration?.title = image == nil ? "사진 첨부" : "사진 변경"
        picker.dismiss(animated: true)
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
#endif

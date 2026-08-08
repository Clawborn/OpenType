import UIKit

final class KeyboardViewController: UIInputViewController {
    private let appGroupIdentifier = "group.ai.opentype.shared"
    private let latestResultKey = "latestGeneratedResult"
    private let latestResultDateKey = "latestGeneratedResultDate"
    private let languageKey = "interfaceLanguage"

    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let statusLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let openAppButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)

    private var isEnglish: Bool {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: languageKey) == "english"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        reloadLatestResult()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadLatestResult()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        reloadLatestResult()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "OpenType"

        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.numberOfLines = 2

        var insertConfig = UIButton.Configuration.filled()
        insertConfig.cornerStyle = .large
        insertConfig.image = UIImage(systemName: "text.cursor")
        insertConfig.imagePadding = 8
        insertButton.configuration = insertConfig
        insertButton.addTarget(self, action: #selector(insertLatestResult), for: .touchUpInside)

        var openConfig = UIButton.Configuration.gray()
        openConfig.cornerStyle = .large
        openConfig.image = UIImage(systemName: "waveform")
        openConfig.imagePadding = 6
        openAppButton.configuration = openConfig
        openAppButton.addTarget(self, action: #selector(openContainingApp), for: .touchUpInside)

        var globeConfig = UIButton.Configuration.plain()
        globeConfig.image = UIImage(systemName: "globe")
        nextKeyboardButton.configuration = globeConfig
        nextKeyboardButton.accessibilityLabel = "Next keyboard"
        nextKeyboardButton.addTarget(self, action: #selector(advanceKeyboard), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), nextKeyboardButton])
        header.axis = .horizontal
        header.alignment = .center

        let buttons = UIStackView(arrangedSubviews: [openAppButton, insertButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillProportionally

        let stack = UIStackView(arrangedSubviews: [header, previewLabel, buttons, statusLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10),
            insertButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            openAppButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func reloadLatestResult() {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let result = defaults?.string(forKey: latestResultKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        previewLabel.text = result.isEmpty
            ? local("还没有生成结果。请先打开 OpenType 说话。", "No result yet. Open OpenType and record first.")
            : result
        insertButton.configuration?.title = local("插入最近结果", "Insert latest result")
        openAppButton.configuration?.title = local("打开并说话", "Open & record")
        insertButton.isEnabled = !result.isEmpty && hasFullAccess

        if !hasFullAccess {
            statusLabel.text = local(
                "请在系统键盘设置中开启“允许完全访问”，用于读取 App Group 结果。键盘本身不能录音。",
                "Enable Allow Full Access to read the App Group result. The keyboard itself cannot record."
            )
        } else if let timestamp = defaults?.object(forKey: latestResultDateKey) as? TimeInterval {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            statusLabel.text = local("生成于 ", "Generated ") + formatter.localizedString(for: Date(timeIntervalSince1970: timestamp), relativeTo: Date())
        } else {
            statusLabel.text = local("结果只在本机 App Group 中同步。", "Results sync only through the local App Group.")
        }
    }

    @objc private func insertLatestResult() {
        guard hasFullAccess,
              let result = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: latestResultKey),
              !result.isEmpty else {
            reloadLatestResult()
            return
        }
        textDocumentProxy.insertText(result)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func openContainingApp() {
        guard let url = URL(string: "opentype://compose") else { return }
        extensionContext?.open(url)
    }

    @objc private func advanceKeyboard() {
        advanceToNextInputMode()
    }

    private func local(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

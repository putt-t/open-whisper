import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let sectionSpacing: CGFloat = 20
    private let fieldSpacing: CGFloat = 14
    private let labelFieldGap: CGFloat = 4
    private let store: AppSettingsStore
    private let backendProcess: BackendProcess

    private let providerPopup = NSPopUpButton()
    private let modelInfoLabel = NSTextField(labelWithString: "")
    private let whisperkitModelField = NSTextField()
    private let whisperkitLanguageField = NSTextField()
    private let cleanupEnabledCheckbox = NSButton(checkboxWithTitle: "Enable Cleanup", target: nil, action: nil)
    private let dictionaryInputField = NSTextField()
    private let dictionaryAddButton = NSButton(title: "Add", target: nil, action: nil)
    private let dictionaryDisclosureButton = NSButton(title: "", target: nil, action: nil)
    private let dictionaryScrollView = NSScrollView()
    private let dictionaryListStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let dictionaryFieldIdentifier = NSUserInterfaceItemIdentifier("DictionaryWordField")

    private var whisperkitModelRow: NSView!
    private var whisperkitLanguageRow: NSView!

    private var settings = AppSettings()
    private var dictionaryTerms: [String] = []
    private var dictionaryListExpanded = false

    init(store: AppSettingsStore, backendProcess: BackendProcess) {
        self.store = store
        self.backendProcess = backendProcess

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open Whisper Settings"
        super.init(window: window)
        window.center()

        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        loadSettings()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func makeLabeledField(_ label: String, control: NSView) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor

        let group = NSStackView(views: [title, control])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = labelFieldGap
        return group
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        return sep
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = fieldSpacing
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            container.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])

        providerPopup.addItems(withTitles: ["qwen", "whisperkit"])
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)

        whisperkitModelField.placeholderString = "openai_whisper-large-v3-v20240930"
        whisperkitLanguageField.placeholderString = "en"

        dictionaryInputField.placeholderString = "Type a word and press Enter"
        dictionaryInputField.target = self
        dictionaryInputField.action = #selector(addDictionaryWordFromInput)

        dictionaryAddButton.target = self
        dictionaryAddButton.action = #selector(addDictionaryWordFromInput)

        dictionaryDisclosureButton.target = self
        dictionaryDisclosureButton.action = #selector(toggleDictionaryList)
        dictionaryDisclosureButton.bezelStyle = .inline

        dictionaryListStack.orientation = .vertical
        dictionaryListStack.spacing = 8
        dictionaryListStack.translatesAutoresizingMaskIntoConstraints = false
        dictionaryListStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let flipped = FlippedClipView()
        flipped.documentView = dictionaryListStack
        dictionaryScrollView.contentView = flipped
        dictionaryScrollView.hasVerticalScroller = true
        dictionaryScrollView.hasHorizontalScroller = false
        dictionaryScrollView.autohidesScrollers = true
        dictionaryScrollView.borderType = .lineBorder
        dictionaryScrollView.translatesAutoresizingMaskIntoConstraints = false
        dictionaryScrollView.isHidden = true
        dictionaryScrollView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        NSLayoutConstraint.activate([
            dictionaryListStack.topAnchor.constraint(equalTo: flipped.topAnchor),
            dictionaryListStack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            dictionaryListStack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
        ])

        cleanupEnabledCheckbox.target = self
        cleanupEnabledCheckbox.action = #selector(cleanupToggled)

        let dictionaryInputRow = NSStackView(views: [dictionaryInputField, dictionaryAddButton])
        dictionaryInputRow.orientation = .horizontal
        dictionaryInputRow.spacing = 8
        dictionaryInputRow.alignment = .centerY


        let sectionHeader1 = makeSectionHeader("Speech Recognition")
        container.addArrangedSubview(sectionHeader1)

        let providerField = makeLabeledField("ASR Provider", control: providerPopup)
        container.addArrangedSubview(providerField)

        modelInfoLabel.font = NSFont.systemFont(ofSize: 11)
        modelInfoLabel.textColor = .secondaryLabelColor
        modelInfoLabel.isSelectable = true
        container.addArrangedSubview(modelInfoLabel)

        whisperkitModelRow = makeLabeledField("WhisperKit Model", control: whisperkitModelField)
        container.addArrangedSubview(whisperkitModelRow)
        whisperkitModelField.leadingAnchor.constraint(equalTo: whisperkitModelRow.leadingAnchor).isActive = true
        whisperkitModelField.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true

        whisperkitLanguageRow = makeLabeledField("WhisperKit Language", control: whisperkitLanguageField)
        container.addArrangedSubview(whisperkitLanguageRow)
        whisperkitLanguageField.leadingAnchor.constraint(equalTo: whisperkitLanguageRow.leadingAnchor).isActive = true
        whisperkitLanguageField.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true

        let sep1 = makeSeparator()
        container.addArrangedSubview(sep1)
        sep1.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        sep1.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        container.setCustomSpacing(sectionSpacing, after: sep1)
        container.addArrangedSubview(makeSectionHeader("Post-Processing"))
        container.addArrangedSubview(cleanupEnabledCheckbox)

        let dictField = makeLabeledField("Add Dictionary Word", control: dictionaryInputRow)
        container.addArrangedSubview(dictField)
        dictionaryInputRow.leadingAnchor.constraint(equalTo: dictField.leadingAnchor).isActive = true
        dictionaryInputRow.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true

        let dictionaryHint = NSTextField(
            labelWithString: "Press Enter/Add. You can also paste a comma/newline list."
        )
        dictionaryHint.textColor = .tertiaryLabelColor
        dictionaryHint.font = NSFont.systemFont(ofSize: 11)
        container.addArrangedSubview(dictionaryHint)

        container.addArrangedSubview(dictionaryDisclosureButton)

        container.addArrangedSubview(dictionaryScrollView)
        dictionaryScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        dictionaryScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true

        let sep2 = makeSeparator()
        container.addArrangedSubview(sep2)
        sep2.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        sep2.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        container.setCustomSpacing(sectionSpacing, after: sep2)


        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePressed))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let openPathButton = NSButton(title: "Show Settings Path", target: self, action: #selector(showSettingsPath))
        openPathButton.bezelStyle = .inline
        openPathButton.contentTintColor = .tertiaryLabelColor

        let buttonRow = NSStackView(views: [saveButton, openPathButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        container.addArrangedSubview(buttonRow)

        statusLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(statusLabel)

    }

    private func resizeWindowToFit() {
        guard let window = window, let contentView = window.contentView else { return }
        let fittingSize = contentView.fittingSize
        let newHeight = fittingSize.height
        var frame = window.frame
        let delta = newHeight - contentView.frame.height
        frame.origin.y -= delta
        frame.size.height += delta
        window.setFrame(frame, display: true, animate: true)
    }

    private func loadSettings() {
        settings = store.load()
        let provider = (settings.asrProvider ?? "qwen").lowercased()
        providerPopup.selectItem(withTitle: provider == "whisperkit" ? "whisperkit" : "qwen")
        whisperkitModelField.stringValue = settings.whisperkitModel ?? ""
        whisperkitLanguageField.stringValue = settings.whisperkitLanguage ?? ""
        cleanupEnabledCheckbox.state = (settings.cleanupEnabled ?? false) ? .on : .off
        dictionaryTerms = splitDictionaryTerms(settings.cleanupUserDictionary ?? "")
        dictionaryTerms = deduplicatedDictionaryTerms(dictionaryTerms)
        dictionaryInputField.stringValue = ""
        dictionaryListExpanded = false
        renderDictionaryRows()
        refreshControlState()
        statusLabel.stringValue = ""
    }

    @objc private func providerChanged() {
        refreshControlState()
    }

    @objc private func cleanupToggled() {
        refreshControlState()
    }

    private func refreshControlState() {
        let whisperkitSelected = providerPopup.titleOfSelectedItem == "whisperkit"
        let cleanupEnabled = cleanupEnabledCheckbox.state == .on

        if whisperkitSelected {
            modelInfoLabel.isHidden = true
        } else {
            modelInfoLabel.stringValue = "Model: mlx-community/Qwen3-ASR-1.7B-6bit"
            modelInfoLabel.isHidden = false
        }

        whisperkitModelRow.isHidden = !whisperkitSelected
        whisperkitLanguageRow.isHidden = !whisperkitSelected
        dictionaryInputField.isEnabled = cleanupEnabled
        dictionaryAddButton.isEnabled = cleanupEnabled
        dictionaryDisclosureButton.isEnabled = cleanupEnabled
        dictionaryScrollView.isHidden = !(cleanupEnabled && dictionaryListExpanded)
        updateDictionaryDisclosureTitle()
    }

    @objc private func addDictionaryWordFromInput() {
        let raw = preprocessDictionaryInput(dictionaryInputField.stringValue)
        guard !raw.isEmpty else { return }

        let incomingTerms = splitDictionaryTerms(raw)
        guard !incomingTerms.isEmpty else { return }

        dictionaryInputField.stringValue = ""
        dictionaryTerms = deduplicatedDictionaryTerms(dictionaryTerms + incomingTerms)
        dictionaryListExpanded = true
        renderDictionaryRows()
        refreshControlState()
    }

    @objc private func toggleDictionaryList() {
        dictionaryListExpanded.toggle()
        refreshControlState()
        resizeWindowToFit()
    }

    @objc private func removeDictionaryWord(_ sender: NSButton) {
        let index = sender.tag
        guard dictionaryTerms.indices.contains(index) else { return }
        dictionaryTerms.remove(at: index)
        renderDictionaryRows()
        refreshControlState()
    }

    private func renderDictionaryRows() {
        for view in dictionaryListStack.arrangedSubviews {
            dictionaryListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !dictionaryTerms.isEmpty else {
            let emptyLabel = NSTextField(labelWithString: "No dictionary words yet.")
            emptyLabel.textColor = .secondaryLabelColor
            dictionaryListStack.addArrangedSubview(emptyLabel)
            return
        }

        for (index, term) in dictionaryTerms.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY

            let wordField = NSTextField(string: term)
            wordField.identifier = dictionaryFieldIdentifier
            wordField.delegate = self
            wordField.tag = index
            wordField.placeholderString = "Dictionary word"

            let removeButton = NSButton(title: "", target: self, action: #selector(removeDictionaryWord))
            removeButton.image = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: "Remove dictionary word"
            )
            removeButton.isBordered = false
            removeButton.contentTintColor = .secondaryLabelColor
            removeButton.tag = index

            row.addArrangedSubview(wordField)
            row.addArrangedSubview(removeButton)
            dictionaryListStack.addArrangedSubview(row)
        }
    }

    private func updateDictionaryDisclosureTitle() {
        let action = dictionaryListExpanded ? "Hide" : "Show"
        dictionaryDisclosureButton.title = "\(action) dictionary words (\(dictionaryTerms.count))"
    }

    @objc private func savePressed() {
        var updated = settings
        updated.asrProvider = providerPopup.titleOfSelectedItem
        updated.whisperkitModel = valueOrNil(whisperkitModelField.stringValue)
        updated.whisperkitLanguage = valueOrNil(whisperkitLanguageField.stringValue)
        updated.cleanupEnabled = cleanupEnabledCheckbox.state == .on
        updated.cleanupUserDictionary = valueOrNil(joinedDictionaryTerms())

        do {
            try store.save(updated)
            settings = updated
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = "Saved. Restarting backend..."
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                do {
                    try self.backendProcess.restart()
                    DispatchQueue.main.async {
                        self.statusLabel.stringValue = "Saved. Backend restarted."
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.statusLabel.textColor = .systemOrange
                        self.statusLabel.stringValue = "Saved, but backend restart failed: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Save failed: \(error.localizedDescription)"
        }
    }

    @objc private func showSettingsPath() {
        let path = store.pathDescription()
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = path
    }

    private func valueOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        guard field.identifier == dictionaryFieldIdentifier else { return }

        let index = field.tag
        guard dictionaryTerms.indices.contains(index) else { return }

        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dictionaryTerms.remove(at: index)
        } else {
            dictionaryTerms[index] = trimmed
        }

        dictionaryTerms = deduplicatedDictionaryTerms(dictionaryTerms)
        renderDictionaryRows()
        refreshControlState()
    }

    private func preprocessDictionaryInput(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "DICTATION_CLEANUP_USER_DICTIONARY="
        if cleaned.uppercased().hasPrefix(key) {
            cleaned = String(cleaned.dropFirst(key.count))
        }

        if cleaned.count >= 2 {
            let first = cleaned.first
            let last = cleaned.last
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitDictionaryTerms(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { preprocessDictionaryInput(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func deduplicatedDictionaryTerms(_ terms: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for term in terms {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                continue
            }
            let normalized = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(normalized).inserted {
                result.append(cleaned)
            }
        }
        return result
    }

    private func joinedDictionaryTerms() -> String {
        dictionaryTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}


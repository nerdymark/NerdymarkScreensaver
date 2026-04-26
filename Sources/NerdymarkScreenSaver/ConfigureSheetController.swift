import Cocoa

/// Programmatic (NIB-less) configure sheet. Builds a vertical stack of
/// controls dynamically based on:
///   - top-level options (scene picker, rotation interval, label toggle)
///   - per-scene options (re-rendered when the picker changes)
///
/// All values write through to the shared SettingsStore on every change so
/// there's no separate "Save" step — Cancel just dismisses without further
/// changes (we deliberately don't snapshot/revert; user changes are live).
final class ConfigureSheetController: NSObject {

    private let settings: SettingsStore
    private(set) var window: NSWindow

    private var scenePicker: NSPopUpButton!
    private var sceneOptionsContainer: NSStackView!
    private var rotationSlider: NSSlider!
    private var rotationLabel: NSTextField!

    init(settings: SettingsStore) {
        self.settings = settings
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.window.title = "Nerdymark Demoscene Settings"
        super.init()
        buildUI()
        rebuildSceneOptions(for: currentSceneIdentifier)
    }

    // MARK: - UI construction

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .left
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let title = NSTextField(labelWithString: "Nerdymark Demoscene")
        title.font = NSFont.boldSystemFont(ofSize: 17)
        root.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "Pick a scene and tune it. Settings save automatically.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = NSFont.systemFont(ofSize: 12)
        root.addArrangedSubview(subtitle)

        root.addArrangedSubview(divider())

        // Scene picker
        let pickerRow = labeledRow(label: "Scene:") {
            let popup = NSPopUpButton()
            for item in SceneRegistry.pickerItems {
                popup.addItem(withTitle: item.label)
                popup.lastItem?.representedObject = item.identifier
            }
            popup.target = self
            popup.action = #selector(sceneChanged(_:))
            self.scenePicker = popup
            return popup
        }
        root.addArrangedSubview(pickerRow)

        // Set picker to current selection.
        let current = currentSceneIdentifier
        if let idx = SceneRegistry.pickerItems.firstIndex(where: { $0.identifier == current }) {
            scenePicker.selectItem(at: idx)
        }

        // Rotation interval (only meaningful when "Random" is picked, but always shown).
        let rotationRow = NSStackView()
        rotationRow.orientation = .horizontal
        rotationRow.spacing = 8
        rotationRow.alignment = .centerY

        let rotLabel = NSTextField(labelWithString: "Random rotation:")
        rotLabel.preferredMaxLayoutWidth = 130
        rotationRow.addArrangedSubview(rotLabel)

        rotationSlider = NSSlider(value: settings.double(SettingsStore.Key.rotationSeconds, default: 90),
                                   minValue: 15, maxValue: 600,
                                   target: self, action: #selector(rotationChanged(_:)))
        rotationSlider.isContinuous = true
        rotationRow.addArrangedSubview(rotationSlider)

        rotationLabel = NSTextField(labelWithString: "")
        rotationLabel.alignment = .right
        rotationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        rotationLabel.textColor = .secondaryLabelColor
        updateRotationLabel()
        rotationRow.addArrangedSubview(rotationLabel)
        root.addArrangedSubview(rotationRow)

        // Label toggle
        let labelToggle = NSButton(checkboxWithTitle: "Show scene name in corner",
                                    target: self, action: #selector(labelToggleChanged(_:)))
        labelToggle.state = settings.bool(SettingsStore.Key.showSceneLabel, default: true) ? .on : .off
        root.addArrangedSubview(labelToggle)

        root.addArrangedSubview(divider())

        // Per-scene options container
        let sectionTitle = NSTextField(labelWithString: "Scene options")
        sectionTitle.font = NSFont.boldSystemFont(ofSize: 13)
        root.addArrangedSubview(sectionTitle)

        sceneOptionsContainer = NSStackView()
        sceneOptionsContainer.orientation = .vertical
        sceneOptionsContainer.alignment = .left
        sceneOptionsContainer.spacing = 10
        root.addArrangedSubview(sceneOptionsContainer)

        // Spacer + close button
        root.addArrangedSubview(NSView())   // flexible spacer
        let closeButton = NSButton(title: "Done", target: self, action: #selector(close(_:)))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [NSView(), closeButton])
        buttonRow.distribution = .fill
        root.addArrangedSubview(buttonRow)

        // Mount in window
        window.contentView = root
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func labeledRow(label labelText: String, control: () -> NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        let label = NSTextField(labelWithString: labelText)
        label.preferredMaxLayoutWidth = 130
        row.addArrangedSubview(label)
        row.addArrangedSubview(control())
        return row
    }

    // MARK: - Per-scene options

    private var currentSceneIdentifier: String {
        return settings.string(SettingsStore.Key.selectedScene, default: SceneRegistry.defaultSelection)
    }

    private func rebuildSceneOptions(for sceneIdentifier: String) {
        // Remove old controls.
        sceneOptionsContainer.arrangedSubviews.forEach { v in
            sceneOptionsContainer.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        if sceneIdentifier == SceneRegistry.randomIdentifier {
            let note = NSTextField(labelWithString: "Random mode rotates through every scene using its saved options.\nPick a specific scene above to tune that scene.")
            note.textColor = .secondaryLabelColor
            note.lineBreakMode = .byWordWrapping
            note.maximumNumberOfLines = 0
            note.preferredMaxLayoutWidth = 420
            sceneOptionsContainer.addArrangedSubview(note)
            return
        }

        guard let sceneType = SceneRegistry.scene(for: sceneIdentifier) else { return }
        let sceneSettings = settings.sceneSettings(for: sceneType.identifier)

        if sceneType.options.isEmpty {
            let note = NSTextField(labelWithString: "This scene has no tunable options.")
            note.textColor = .secondaryLabelColor
            sceneOptionsContainer.addArrangedSubview(note)
            return
        }

        for option in sceneType.options {
            sceneOptionsContainer.addArrangedSubview(controlRow(for: option, scene: sceneType, sceneSettings: sceneSettings))
        }
    }

    private func controlRow(for option: SceneOption, scene: DemoScene.Type, sceneSettings: SceneSettings) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let label = NSTextField(labelWithString: option.label + ":")
        label.preferredMaxLayoutWidth = 130
        row.addArrangedSubview(label)

        switch option {
        case .slider(let key, _, let mn, let mx, let dflt, let format):
            let value = sceneSettings.double(key, default: dflt)
            let slider = NSSlider(value: value, minValue: mn, maxValue: mx,
                                   target: nil, action: nil)
            slider.isContinuous = true
            let valueLabel = NSTextField(labelWithString: String(format: format, value))
            valueLabel.alignment = .right
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueLabel.textColor = .secondaryLabelColor
            valueLabel.preferredMaxLayoutWidth = 80

            let proxy = SliderProxy(settings: settings, sceneId: scene.identifier, key: key, format: format, label: valueLabel)
            slider.target = proxy
            slider.action = #selector(SliderProxy.changed(_:))
            // Retain the proxy by attaching it to the slider as an associated object via objc_setAssociatedObject.
            objc_setAssociatedObject(slider, &SliderProxy.assocKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            row.addArrangedSubview(slider)
            row.addArrangedSubview(valueLabel)

        case .toggle(let key, _, let dflt):
            let value = sceneSettings.bool(key, default: dflt)
            let proxy = ToggleProxy(settings: settings, sceneId: scene.identifier, key: key)
            let cb = NSButton(checkboxWithTitle: "", target: proxy, action: #selector(ToggleProxy.changed(_:)))
            cb.state = value ? .on : .off
            objc_setAssociatedObject(cb, &ToggleProxy.assocKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            row.addArrangedSubview(cb)

        case .choice(let key, _, let choices, let dflt):
            let value = sceneSettings.string(key, default: dflt)
            let popup = NSPopUpButton()
            for c in choices {
                popup.addItem(withTitle: c)
                popup.lastItem?.representedObject = c
            }
            popup.selectItem(withTitle: value)
            let proxy = ChoiceProxy(settings: settings, sceneId: scene.identifier, key: key)
            popup.target = proxy
            popup.action = #selector(ChoiceProxy.changed(_:))
            objc_setAssociatedObject(popup, &ChoiceProxy.assocKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            row.addArrangedSubview(popup)

        case .text(let key, _, let dflt, let placeholder):
            let value = sceneSettings.string(key, default: dflt)
            let field = NSTextField(string: value)
            field.placeholderString = placeholder
            field.bezelStyle = .roundedBezel
            field.preferredMaxLayoutWidth = 260
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            let proxy = TextProxy(settings: settings, sceneId: scene.identifier, key: key)
            field.target = proxy
            field.action = #selector(TextProxy.changed(_:))
            field.delegate = proxy   // saves on focus loss too
            objc_setAssociatedObject(field, &TextProxy.assocKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            row.addArrangedSubview(field)
        }
        return row
    }

    // MARK: - Top-level actions

    @objc private func sceneChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let item = SceneRegistry.pickerItems[idx]
        settings.set(item.identifier, for: SettingsStore.Key.selectedScene)
        rebuildSceneOptions(for: item.identifier)
    }

    @objc private func rotationChanged(_ sender: NSSlider) {
        settings.set(sender.doubleValue, for: SettingsStore.Key.rotationSeconds)
        updateRotationLabel()
    }

    @objc private func labelToggleChanged(_ sender: NSButton) {
        settings.set(sender.state == .on, for: SettingsStore.Key.showSceneLabel)
    }

    @objc private func close(_ sender: Any?) {
        window.sheetParent?.endSheet(window)
    }

    private func updateRotationLabel() {
        let v = Int(rotationSlider.doubleValue)
        rotationLabel.stringValue = "\(v)s"
    }
}

// MARK: - Action proxies (so each control persists changes independently)

private final class SliderProxy: NSObject {
    static var assocKey: UInt8 = 0
    let settings: SettingsStore
    let sceneId: String
    let key: String
    let format: String
    weak var label: NSTextField?

    init(settings: SettingsStore, sceneId: String, key: String, format: String, label: NSTextField) {
        self.settings = settings
        self.sceneId = sceneId
        self.key = key
        self.format = format
        self.label = label
    }

    @objc func changed(_ sender: NSSlider) {
        let nsKey = "scene.\(sceneId).\(key)"
        settings.set(sender.doubleValue, for: nsKey)
        label?.stringValue = String(format: format, sender.doubleValue)
    }
}

private final class ToggleProxy: NSObject {
    static var assocKey: UInt8 = 0
    let settings: SettingsStore
    let sceneId: String
    let key: String

    init(settings: SettingsStore, sceneId: String, key: String) {
        self.settings = settings
        self.sceneId = sceneId
        self.key = key
    }

    @objc func changed(_ sender: NSButton) {
        let nsKey = "scene.\(sceneId).\(key)"
        settings.set(sender.state == .on, for: nsKey)
    }
}

private final class ChoiceProxy: NSObject {
    static var assocKey: UInt8 = 0
    let settings: SettingsStore
    let sceneId: String
    let key: String

    init(settings: SettingsStore, sceneId: String, key: String) {
        self.settings = settings
        self.sceneId = sceneId
        self.key = key
    }

    @objc func changed(_ sender: NSPopUpButton) {
        let nsKey = "scene.\(sceneId).\(key)"
        settings.set(sender.titleOfSelectedItem ?? "", for: nsKey)
    }
}

private final class TextProxy: NSObject, NSTextFieldDelegate {
    static var assocKey: UInt8 = 0
    let settings: SettingsStore
    let sceneId: String
    let key: String

    init(settings: SettingsStore, sceneId: String, key: String) {
        self.settings = settings
        self.sceneId = sceneId
        self.key = key
    }

    @objc func changed(_ sender: NSTextField) {
        let nsKey = "scene.\(sceneId).\(key)"
        settings.set(sender.stringValue, for: nsKey)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let nsKey = "scene.\(sceneId).\(key)"
        settings.set(field.stringValue, for: nsKey)
    }
}

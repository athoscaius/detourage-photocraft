import AppKit
import Foundation
import Darwin

// Palette and small-radius controls follow PhotoCraft's Pro panel grammar.
private enum EditorPalette {
    static let chrome = NSColor(white: 50.0 / 255, alpha: 1)
    static let canvas = NSColor(white: 40.0 / 255, alpha: 1)
    static let field = NSColor(white: 36.0 / 255, alpha: 1)
    static let border = NSColor(white: 74.0 / 255, alpha: 1)
    static let separator = NSColor(white: 30.0 / 255, alpha: 1)
    static let hover = NSColor(white: 66.0 / 255, alpha: 1)
    static let selected = NSColor(white: 78.0 / 255, alpha: 1)
    static let text = NSColor(white: 222.0 / 255, alpha: 1)
    static let dim = NSColor(white: 178.0 / 255, alpha: 1)
    static let accent = NSColor(srgbRed: 55.0 / 255, green: 142.0 / 255, blue: 240.0 / 255, alpha: 1)
    static let danger = NSColor(srgbRed: 236.0 / 255, green: 91.0 / 255, blue: 98.0 / 255, alpha: 1)
}

private final class EditorButton: NSButton {
    var primary = false
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        let selected = state == .on
        let fill: NSColor
        if !isEnabled { fill = EditorPalette.chrome }
        else if isHighlighted { fill = primary ? EditorPalette.accent.blended(withFraction: 0.18, of: .black) ?? EditorPalette.accent : EditorPalette.hover }
        else { fill = primary ? EditorPalette.accent : (selected ? EditorPalette.selected : EditorPalette.field) }
        fill.setFill(); path.fill()
        (selected || window?.firstResponder === self ? EditorPalette.accent : EditorPalette.border).setStroke()
        path.lineWidth = 1; path.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: isEnabled ? (primary ? NSColor.white : EditorPalette.text) : EditorPalette.dim.withAlphaComponent(0.45),
            .paragraphStyle: paragraph
        ]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 9, y: (bounds.height - height) / 2,
            width: bounds.width - 18, height: height + 1), withAttributes: attributes)
    }
}

private final class EditorChoice: NSView {
    private var options: [EditorButton] = []
    var onChange: (() -> Void)?
    var selectedSegment = 0 { didSet { refresh() } }
    var isEnabled = true { didSet { options.forEach { $0.isEnabled = isEnabled; $0.needsDisplay = true } } }
    init(_ titles: [String]) {
        super.init(frame: .zero)
        options = titles.enumerated().map { index, title in
            let button = EditorButton(frame: .zero)
            button.title = title; button.tag = index
            button.target = self; button.action = #selector(choose(_:))
            button.font = .systemFont(ofSize: 13)
            button.isBordered = false
            button.setAccessibilityRole(.radioButton)
            return button
        }
        let stack = NSStackView(views: options)
        stack.orientation = .horizontal; stack.distribution = .fillEqually; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for option in options {
            option.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refresh()
    }
    required init?(coder: NSCoder) { return nil }
    @objc private func choose(_ sender: EditorButton) { selectedSegment = sender.tag; onChange?() }
    private func refresh() {
        for option in options {
            option.state = option.tag == selectedSegment ? .on : .off
            option.setAccessibilityValue(option.tag == selectedSegment ? 1 : 0)
            option.needsDisplay = true
        }
    }
}

// Indeterminate on purpose: the model does not expose per-layer completion.
// The moving blue segment indicates activity without inventing a percentage.
private final class EditorLoadingBar: NSView {
    var phase: Double = 0 { didSet { needsDisplay = true } }
    var completed = false { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Progression du détourage")
    }
    required init?(coder: NSCoder) { return nil }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - 4) / 2, width: bounds.width, height: 4)
        let path = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        EditorPalette.field.setFill(); path.fill()
        guard bounds.width > 0 else { return }
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        let width = completed ? bounds.width : max(40, bounds.width * 0.28)
        let position = completed ? 0 : (bounds.width + width) * CGFloat(phase.truncatingRemainder(dividingBy: 1)) - width
        EditorPalette.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: position, y: track.minY, width: width, height: 4), xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private let hostBundleIdentifier = "ai.storyteller.photocraft"
private let controlPort: UInt16 = 47863

final class CompanionDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var launchButton: NSButton!
    private var personButton: NSButton!
    private var subjectControl: EditorChoice!
    private var resultHelpLabel: NSTextField!
    private var sourceLabel: NSTextField!
    private var diagnoseButton: NSButton!
    private var outputControl: EditorChoice!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progress: EditorLoadingBar!
    private var loadingRow: NSStackView!
    private var elapsedLabel: NSTextField!
    private var loadingTimer: Timer?
    private var loadingStarted: TimeInterval?
    private var loadingDuration: TimeInterval = 0
    private var menuPerson: NSMenuItem!
    private var menuSubject: NSMenuItem!
    private var menuLaunch: NSMenuItem!
    private var menuDiagnose: NSMenuItem!
    private var busy = false
    private var lastMatte: URL?
    private let worker = DispatchQueue(label: "fr.artcraft.detourage.worker", qos: .userInitiated)

    private var supportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ArtCraft Detourage IA", isDirectory: true)
    }
    private var workURL: URL { supportURL.appendingPathComponent("work", isDirectory: true) }
    private var tokenURL: URL { supportURL.appendingPathComponent("control.token") }
    private var resourceURL: URL? { Bundle.main.resourceURL }
    private var hostIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: hostBundleIdentifier).isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon-v3", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        makeMenuBar()
        makeWindow()
        makeStatusItem()
        do {
            try prepareDirectories()
            showStatus("Prêt", detail: "Ouvrez votre image dans PhotoCraft, puis choisissez le résultat souhaité.")
        } catch {
            showError("Impossible de préparer le dossier de travail : \(error.localizedDescription)")
        }
        showWindow(nil)
        worker.async { [weak self] in
            guard Self.localPortIsReachable() else { return }
            DispatchQueue.main.async {
                guard let self = self, !self.busy else { return }
                self.runBridge(diagnoseOnly: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard busy else { return .terminateNow }
        showWindow(nil)
        let alert = NSAlert()
        alert.messageText = "Un détourage est en cours"
        alert.informativeText = "Laissez le calcul se terminer avant de quitter le compagnon."
        alert.addButton(withTitle: "Continuer le calcul")
        alert.runModal()
        return .terminateCancel
    }

    private func prepareDirectories() throws {
        if let script = resourceURL?.appendingPathComponent("source/configure_connection.py"),
           FileManager.default.fileExists(atPath: script.path) {
            let setup = Process()
            setup.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            setup.arguments = [script.path]
            setup.standardOutput = FileHandle.nullDevice
            setup.standardError = FileHandle.nullDevice
            try setup.run()
            setup.waitUntilExit()
            guard setup.terminationStatus == 0 else {
                throw NSError(domain: "ArtCraftConnection", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "La configuration de connexion automatique a échoué."])
            }
        }
        for directory in [supportURL, workURL] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    private func makeMenuBar() {
        let menuBar = NSMenu()
        let appItem = NSMenuItem()
        menuBar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Afficher Détourage IA", action: #selector(showWindow(_:)), keyEquivalent: "1").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quitter Détourage IA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApplication.shared.mainMenu = menuBar
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "person.crop.rectangle.badge.plus", accessibilityDescription: "Détourage IA")
        statusItem.button?.toolTip = "ArtCraft · Détourage IA"
        let menu = NSMenu()
        menu.addItem(withTitle: "Afficher le compagnon", action: #selector(showWindow(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menuLaunch = menu.addItem(withTitle: "Ouvrir PhotoCraft", action: #selector(launchHost(_:)), keyEquivalent: "")
        menuPerson = menu.addItem(withTitle: "Sélectionner la personne", action: #selector(selectPerson(_:)), keyEquivalent: "")
        menuSubject = menu.addItem(withTitle: "Sélectionner le sujet", action: #selector(selectSubject(_:)), keyEquivalent: "")
        menuDiagnose = menu.addItem(withTitle: "Vérifier la connexion", action: #selector(diagnose(_:)), keyEquivalent: "")
        for item in [menuLaunch, menuPerson, menuSubject, menuDiagnose] { item?.target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Afficher le dernier masque PNG", action: #selector(revealMatte(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    private func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = EditorPalette.text) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = true
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    private func button(_ title: String, selector: Selector, symbol: String? = nil) -> NSButton {
        let button = EditorButton(frame: .zero)
        button.title = title; button.target = self; button.action = selector
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func surface(_ color: NSColor) -> NSView {
        let view = NSView()
        view.wantsLayer = true; view.layer?.backgroundColor = color.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ArtCraft · Détourage IA"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = EditorPalette.chrome
        window.contentMinSize = NSSize(width: 600, height: 580)
        window.delegate = self; window.isReleasedWhenClosed = false
        window.center()
        let content = surface(EditorPalette.canvas)
        window.contentView = content

        let header = surface(EditorPalette.chrome)
        let sourceTitle = label("PhotoCraft", size: 13, weight: .semibold)
        sourceLabel = label("Image ouverte dans PhotoCraft", size: 11, color: EditorPalette.dim)
        sourceLabel.maximumNumberOfLines = 1; sourceLabel.lineBreakMode = .byTruncatingTail
        let source = NSStackView(views: [sourceTitle, sourceLabel])
        source.orientation = .vertical; source.alignment = .leading; source.spacing = 4
        source.translatesAutoresizingMaskIntoConstraints = false
        launchButton = button("Ouvrir PhotoCraft", selector: #selector(launchHost(_:)))
        launchButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(source); header.addSubview(launchButton)
        content.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor), header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 66),
            source.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24), source.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            source.trailingAnchor.constraint(lessThanOrEqualTo: launchButton.leadingAnchor, constant: -20),
            launchButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            launchButton.centerYAnchor.constraint(equalTo: header.centerYAnchor), launchButton.widthAnchor.constraint(equalToConstant: 148)
        ])

        let tabBar = surface(NSColor(white: 38.0 / 255, alpha: 1))
        let tab = label("Détourage", size: 12, weight: .semibold)
        tab.translatesAutoresizingMaskIntoConstraints = false
        let accent = surface(EditorPalette.accent)
        let local = label("IA locale", size: 11, color: EditorPalette.dim)
        local.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tab); tabBar.addSubview(accent); tabBar.addSubview(local)
        content.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor), tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: header.bottomAnchor), tabBar.heightAnchor.constraint(equalToConstant: 38),
            tab.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 24), tab.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            accent.leadingAnchor.constraint(equalTo: tab.leadingAnchor), accent.widthAnchor.constraint(equalToConstant: 65),
            accent.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor), accent.heightAnchor.constraint(equalToConstant: 2),
            local.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -24), local.centerYAnchor.constraint(equalTo: tab.centerYAnchor)
        ])

        let footer = surface(EditorPalette.chrome)
        content.addSubview(footer)
        personButton = button("Sélectionner la personne", selector: #selector(selectCurrent(_:)))
        (personButton as? EditorButton)?.primary = true
        personButton.font = .systemFont(ofSize: 13, weight: .medium)
        personButton.keyEquivalent = "\r"
        personButton.toolTip = "Lancer le détourage avec les paramètres choisis."
        personButton.translatesAutoresizingMaskIntoConstraints = false
        let privacy = label("Traitement sur ce Mac", size: 11, color: EditorPalette.dim)
        privacy.toolTip = "Aucune photo n’est envoyée à un service externe."
        privacy.translatesAutoresizingMaskIntoConstraints = false
        let footerLine = surface(EditorPalette.separator)
        footer.addSubview(privacy); footer.addSubview(personButton); footer.addSubview(footerLine)
        NSLayoutConstraint.activate([
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor), footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor), footer.heightAnchor.constraint(equalToConstant: 76),
            footerLine.topAnchor.constraint(equalTo: footer.topAnchor), footerLine.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: footer.trailingAnchor), footerLine.heightAnchor.constraint(equalToConstant: 1),
            privacy.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24), privacy.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            personButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24), personButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            personButton.widthAnchor.constraint(equalToConstant: 222)
        ])

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: tabBar.bottomAnchor), body.bottomAnchor.constraint(equalTo: footer.topAnchor),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28)
        ])
        let sectionTitle = label("Paramètres", size: 12, weight: .semibold)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(sectionTitle)
        subjectControl = EditorChoice(["Personne", "Autre sujet"])
        outputControl = EditorChoice(["Sélection fine", "Masque de calque"])
        subjectControl.onChange = { [weak self] in self?.updateChoices() }
        outputControl.onChange = { [weak self] in self?.updateChoices() }
        let subjectRow = formRow("Détecter", control: subjectControl)
        let outputRow = formRow("Créer", control: outputControl)
        resultHelpLabel = label("Sélection douce, ajustable dans PhotoCraft.", size: 12, color: EditorPalette.dim)
        resultHelpLabel.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(subjectRow)
        body.addSubview(outputRow)
        body.addSubview(resultHelpLabel)
        NSLayoutConstraint.activate([
            sectionTitle.topAnchor.constraint(equalTo: body.topAnchor, constant: 27), sectionTitle.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            subjectRow.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 22), subjectRow.leadingAnchor.constraint(equalTo: body.leadingAnchor), subjectRow.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            outputRow.topAnchor.constraint(equalTo: subjectRow.bottomAnchor, constant: 22), outputRow.leadingAnchor.constraint(equalTo: body.leadingAnchor), outputRow.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            resultHelpLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 96),
            resultHelpLabel.trailingAnchor.constraint(equalTo: body.trailingAnchor), resultHelpLabel.topAnchor.constraint(equalTo: outputRow.bottomAnchor, constant: 10)
        ])

        let statusPanel = surface(EditorPalette.chrome)
        statusPanel.layer?.cornerRadius = 4
        statusPanel.layer?.borderColor = EditorPalette.separator.cgColor
        statusPanel.layer?.borderWidth = 1
        body.addSubview(statusPanel)
        statusLabel = label("Prêt", size: 13, weight: .medium)
        detailLabel = label("", size: 12, color: EditorPalette.dim)
        detailLabel.maximumNumberOfLines = 5; detailLabel.preferredMaxLayoutWidth = 500
        progress = EditorLoadingBar(frame: .zero)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 16).isActive = true
        elapsedLabel = label("Temps écoulé · 00:00", size: 11, color: EditorPalette.dim)
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        elapsedLabel.setContentHuggingPriority(.required, for: .horizontal)
        elapsedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        loadingRow = NSStackView(views: [progress, elapsedLabel])
        loadingRow.orientation = .horizontal; loadingRow.alignment = .centerY; loadingRow.spacing = 16
        loadingRow.isHidden = true
        diagnoseButton = button("↻", selector: #selector(diagnose(_:)))
        diagnoseButton.font = .systemFont(ofSize: 17)
        diagnoseButton.toolTip = "Vérifier la connexion à PhotoCraft"
        diagnoseButton.setAccessibilityLabel("Vérifier la connexion")
        diagnoseButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let statusHeading = NSStackView(views: [statusLabel, NSView(), diagnoseButton])
        statusHeading.orientation = .horizontal; statusHeading.spacing = 8
        let statusStack = NSStackView(views: [statusHeading, detailLabel, loadingRow])
        statusStack.orientation = .vertical; statusStack.alignment = .leading; statusStack.spacing = 7
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusPanel.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusPanel.topAnchor.constraint(equalTo: resultHelpLabel.bottomAnchor, constant: 30),
            statusPanel.leadingAnchor.constraint(equalTo: body.leadingAnchor), statusPanel.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            statusPanel.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor, constant: -24),
            statusStack.topAnchor.constraint(equalTo: statusPanel.topAnchor, constant: 12), statusStack.bottomAnchor.constraint(equalTo: statusPanel.bottomAnchor, constant: -16),
            statusStack.leadingAnchor.constraint(equalTo: statusPanel.leadingAnchor, constant: 16), statusStack.trailingAnchor.constraint(equalTo: statusPanel.trailingAnchor, constant: -16),
            loadingRow.widthAnchor.constraint(equalTo: statusStack.widthAnchor),
            statusHeading.widthAnchor.constraint(equalTo: statusStack.widthAnchor), detailLabel.widthAnchor.constraint(equalTo: statusStack.widthAnchor),
            statusPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
    }

    private func formRow(_ title: String, control: NSView) -> NSView {
        let caption = label(title, size: 13, color: EditorPalette.dim)
        let row = NSStackView(views: [caption, control])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        caption.widthAnchor.constraint(equalToConstant: 80).isActive = true
        row.heightAnchor.constraint(equalToConstant: 34).isActive = true
        control.heightAnchor.constraint(equalToConstant: 34).isActive = true
        control.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -96).isActive = true
        return row
    }

    private func updateChoices() {
        personButton.title = subjectControl.selectedSegment == 0 ? "Sélectionner la personne" : "Sélectionner le sujet"
        personButton.needsDisplay = true
        resultHelpLabel.stringValue = outputControl.selectedSegment == 0
            ? "Sélection douce, ajustable dans PhotoCraft."
            : "Masque modifiable sur le calque actif."
    }

    @objc private func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showStatus(_ title: String, detail: String, error: Bool = false) {
        statusLabel.stringValue = title
        statusLabel.textColor = error ? EditorPalette.danger : EditorPalette.text
        detailLabel.stringValue = detail
        detailLabel.toolTip = detail
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func showError(_ message: String) {
        showStatus("Action à vérifier", detail: message, error: true)
        showWindow(nil)
    }

    private func setBusy(_ value: Bool) {
        busy = value
        for control in [launchButton, personButton, diagnoseButton] { control?.isEnabled = !value }
        outputControl.isEnabled = !value
        subjectControl.isEnabled = !value
        for item in [menuPerson, menuSubject, menuLaunch, menuDiagnose] { item?.isEnabled = !value }
        loadingTimer?.invalidate(); loadingTimer = nil
        if value {
            loadingStarted = ProcessInfo.processInfo.systemUptime
            loadingDuration = 0
            progress.completed = false
            loadingRow.isHidden = false
            updateLoadingClock()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateLoadingClock() }
            loadingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            if let start = loadingStarted { loadingDuration = ProcessInfo.processInfo.systemUptime - start }
            loadingStarted = nil
            loadingRow.isHidden = true
        }
        statusItem.button?.toolTip = value ? "Détourage IA · opération en cours" : "ArtCraft · Détourage IA"
    }

    private func updateLoadingClock() {
        guard let start = loadingStarted else { return }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - start)
        progress.phase = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.35 : elapsed / 1.8
        elapsedLabel.stringValue = "Temps écoulé · " + Self.durationText(elapsed)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func showCompletedLoading() {
        progress.completed = true
        elapsedLabel.stringValue = "Durée · " + Self.durationText(loadingDuration)
        loadingRow.isHidden = false
    }

    @objc private func launchHost(_ sender: Any?) {
        guard !busy else { return }
        do { try prepareDirectories() } catch {
            showError("Impossible de préparer le dossier de travail : \(error.localizedDescription)")
            return
        }
        if hostIsRunning {
            runBridge(diagnoseOnly: true)
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hostBundleIdentifier) else {
            showError("PhotoCraft est introuvable sur ce Mac. Installez PhotoCraft, puis réessayez.")
            return
        }
        setBusy(true)
        showStatus("Ouverture de PhotoCraft…", detail: "La connexion locale sera activée pour cette session.")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--control", String(controlPort), "--control-token-file", tokenURL.path,
                                   "--automation-read-root", workURL.path, "--automation-write-root", workURL.path]
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false)
                if let error = error {
                    self.showError("PhotoCraft n’a pas pu s’ouvrir : \(error.localizedDescription)")
                } else {
                    self.showStatus("PhotoCraft ouvert", detail: "Ouvrez votre image, puis revenez au détourage.")
                }
            }
        }
    }

    @objc private func selectCurrent(_ sender: Any?) { runBridge(mode: subjectControl.selectedSegment == 0 ? "person" : "subject") }
    @objc private func selectPerson(_ sender: Any?) { subjectControl.selectedSegment = 0; updateChoices(); runBridge(mode: "person") }
    @objc private func selectSubject(_ sender: Any?) { subjectControl.selectedSegment = 1; updateChoices(); runBridge(mode: "subject") }
    @objc private func diagnose(_ sender: Any?) { runBridge(diagnoseOnly: true) }

    private func connectionInstructions() -> String {
        if hostIsRunning {
            return "La connexion automatique est configurée pour les prochains lancements. Pour cette session démarrée sans connexion, enregistrez vos documents, quittez PhotoCraft puis rouvrez-le. Vous pourrez ensuite lancer PhotoCraft normalement. Si le démarrage est en cours, patientez quelques secondes puis actualisez."
        }
        return "Cliquez sur « Ouvrir PhotoCraft » dans ce compagnon, puis ouvrez votre photo."
    }

    private func runBridge(mode: String = "person", diagnoseOnly: Bool = false) {
        guard !busy else { return }
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            showError(connectionInstructions())
            return
        }
        guard let resources = resourceURL else {
            showError("Les ressources du compagnon sont introuvables. Réinstallez le compagnon.")
            return
        }
        let bridge = resources.appendingPathComponent("source/photocraft_bridge.py")
        let engine = resources.appendingPathComponent("bin/matting-engine")
        guard FileManager.default.fileExists(atPath: bridge.path),
              diagnoseOnly || FileManager.default.isExecutableFile(atPath: engine.path),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            showError("Le moteur ou Python 3 est introuvable. Réinstallez le compagnon et les outils de ligne de commande Apple si nécessaire.")
            return
        }
        do { try prepareDirectories() } catch {
            showError("Impossible d’accéder au dossier de travail : \(error.localizedDescription)")
            return
        }
        let output = outputControl.selectedSegment == 1 ? "mask" : "selection"
        var arguments = [bridge.path, "--root", workURL.path, "--port", String(controlPort),
                         "--token-file", tokenURL.path, "--engine", engine.path,
                         "--mode", mode, "--output", output]
        if diagnoseOnly { arguments.append("--diagnose") }
        let instructions = connectionInstructions()
        setBusy(true)
        showStatus(diagnoseOnly ? "Connexion à PhotoCraft…" : "Détourage en cours…",
                   detail: diagnoseOnly ? "Vérification de la connexion locale." : "Gardez la même image et le même calque actifs pendant le calcul.")
        worker.async { [weak self] in
            guard Self.localPortIsReachable() else {
                DispatchQueue.main.async {
                    self?.setBusy(false)
                    self?.showError(instructions)
                }
                return
            }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ProcessInfo.processInfo.environment.merging(["PYTHONUTF8": "1"]) { _, new in new }
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                let json = text.split(separator: "\n").reversed().compactMap { line -> [String: Any]? in
                    guard let lineData = String(line).data(using: .utf8) else { return nil }
                    return (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
                }.first
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.setBusy(false)
                    guard let json = json else {
                        self.showError("Le moteur n’a pas renvoyé de résultat valide. " + String(text.suffix(800)))
                        return
                    }
                    if process.terminationStatus != 0 || json["ok"] as? Bool != true {
                        let message = json["error"] as? String ?? "Le détourage n’a pas pu se terminer."
                        let kind = json["kind"] as? String ?? ""
                        self.showError(["connection", "authentication"].contains(kind) ? message + " " + instructions : message)
                        return
                    }
                    if diagnoseOnly {
                        let document = json["activeDocument"] as? String
                        self.sourceLabel.stringValue = document ?? "Aucune photo ouverte"
                        self.sourceLabel.toolTip = document
                        self.showStatus("PhotoCraft connecté", detail: document.map { "Prêt à sélectionner dans « \($0) »." } ?? "Ouvrez une image dans PhotoCraft pour commencer.")
                    } else {
                        self.showCompletedLoading()
                        if let path = json["matte"] as? String { self.lastMatte = URL(fileURLWithPath: path) }
                        let document = json["document"] as? String ?? "votre photo"
                        self.sourceLabel.stringValue = document
                        self.sourceLabel.toolTip = document
                        var detail = "Le résultat est appliqué à « \(document) ». Vous pouvez poursuivre vos retouches dans PhotoCraft."
                        if let warning = json["warning"] as? String { detail += " " + warning }
                        self.showStatus(output == "mask" ? "Masque de calque créé" : "Sélection fine prête", detail: detail)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.setBusy(false)
                    self?.showError("Impossible de lancer le moteur : \(error.localizedDescription)")
                }
            }
        }
    }

    // A short, unauthenticated loopback probe prevents a long wait when the host
    // was launched normally. Authentication is always performed by the bridge.
    private static func localPortIsReachable() -> Bool {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = controlPort.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&pollDescriptor, 1, 800) > 0 else { return false }
        var socketError: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &size) == 0 && socketError == 0
    }

    @objc private func revealMatte(_ sender: Any?) {
        guard let url = lastMatte, FileManager.default.fileExists(atPath: url.path) else {
            showStatus("Aucun masque récent", detail: "Le dernier masque PNG sera disponible ici après un détourage réussi.")
            showWindow(nil)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

let application = NSApplication.shared
let delegate = CompanionDelegate()
application.delegate = delegate
application.run()

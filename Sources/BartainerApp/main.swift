import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let dockerService = DockerService()
    private lazy var containerViewController = ContainerViewController(service: dockerService)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Bartainer"
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.contentSize = NSSize(width: 728, height: 142)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = containerViewController
        containerViewController.onContentHeightChange = { [weak self] height in
            self?.popover.contentSize = NSSize(width: 728, height: height)
        }

        containerViewController.refresh()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        containerViewController.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let box = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3.5, width: 13, height: 11), xRadius: 3, yRadius: 3)
        box.lineWidth = 1.7
        box.stroke()

        for x in [6.0, 9.0, 12.0] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: 5.6))
            line.line(to: NSPoint(x: x, y: 12.4))
            line.lineWidth = 1.1
            line.stroke()
        }

        let cap = NSBezierPath(roundedRect: NSRect(x: 5.4, y: 13.0, width: 7.2, height: 2.3), xRadius: 1.1, yRadius: 1.1)
        cap.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        "B".draw(in: NSRect(x: 2, y: 4.2, width: 14, height: 10), withAttributes: attributes)

        image.isTemplate = true
        image.accessibilityDescription = "Bartainer"
        return image
    }
}

@main
@MainActor
struct BartainerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class ContainerViewController: NSViewController {
    private let service: DockerService
    private let hostStore = HostStore()
    private let rootStack = NSStackView()
    private let tabControl = NSSegmentedControl(labels: ["Containers", "General", "Hosts"], trackingMode: .selectOne, target: nil, action: nil)
    private let contentStack = NSStackView()
    private let containerSection = NSStackView()
    private let generalSection = NSStackView()
    private let hostsSection = NSStackView()
    private let scrollView = NSScrollView()
    private let rowsStack = FlippedStackView()
    private let hostListStack = FlippedStackView()
    private let summaryLabel = NSTextField(labelWithString: "Loading containers...")
    private let spinner = NSProgressIndicator()
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let nameField = NSTextField()
    private let addressField = NSTextField()
    private let userField = NSTextField()
    private let portField = NSTextField(string: "22")
    private let passwordField = NSSecureTextField()
    private var scrollHeightConstraint: NSLayoutConstraint?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var refreshTimer: Timer?
    private var isRefreshing = false
    var onContentHeightChange: ((CGFloat) -> Void)?

    init(service: DockerService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 728, height: 142))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.masksToBounds = true
        view = glass
        buildView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        spinner.startAnimation(nil)

        service.listContainers(hosts: hostStore.load()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.spinner.stopAnimation(nil)

                switch result {
                case .success(let snapshot):
                    self.render(snapshot: snapshot)
                case .failure(let error):
                    self.renderError(error)
                }
            }
        }
    }

    private func buildView() {
        rootStack.orientation = .vertical
        rootStack.spacing = 3
        rootStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        rootStack.addArrangedSubview(toolbar())
        contentStack.orientation = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(contentStack)

        containerSection.orientation = .vertical
        containerSection.spacing = 3
        containerSection.addArrangedSubview(headerRow())

        rowsStack.orientation = .vertical
        rowsStack.spacing = 2
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.documentView = rowsStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerSection.addArrangedSubview(scrollView)

        scrollHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 38)
        scrollHeightConstraint?.isActive = true
        contentStack.addArrangedSubview(containerSection)

        buildGeneralSection()
        buildHostsSection()
        contentStack.addArrangedSubview(generalSection)
        contentStack.addArrangedSubview(hostsSection)
        showTab(index: 0)

        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func toolbar() -> NSView {
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 4, right: 8)

        let title = NSTextField(labelWithString: "Bartainer")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        tabControl.selectedSegment = 0
        tabControl.controlSize = .small
        tabControl.target = self
        tabControl.action = #selector(changeTab)

        summaryLabel.font = .systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let refreshButton = iconButton(symbolName: "arrow.clockwise", action: #selector(refreshFromButton))
        let quitButton = iconButton(symbolName: "power", action: #selector(quit))

        toolbar.addArrangedSubview(title)
        toolbar.addArrangedSubview(tabControl)
        toolbar.addArrangedSubview(summaryLabel)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(spinner)
        toolbar.addArrangedSubview(refreshButton)
        toolbar.addArrangedSubview(quitButton)

        return toolbar
    }

    private func headerRow() -> NSView {
        let row = RowView(isHeader: true)
        row.configure(values: [
            "ID",
            "NAME",
            "TAG",
            "STATE",
            "STATUS",
            "PORTS"
        ], state: nil)
        return row
    }

    private func render(snapshot: DockerSnapshot) {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if snapshot.containers.isEmpty && snapshot.errors.isEmpty {
            summaryLabel.stringValue = "No containers found"
            let empty = EmptyStateView(message: "Docker is running, but there are no containers to show.")
            rowsStack.addArrangedSubview(empty)
            resize(for: 1, emptyOrError: true)
            return
        }

        let containers = snapshot.containers
        let running = containers.filter { $0.state.lowercased() == "running" }.count
        let hostCount = snapshot.hosts.count
        summaryLabel.stringValue = "\(containers.count) total, \(running) running, \(hostCount) hosts"
        let renderedRows = containers.count + snapshot.errors.count + snapshot.hosts.count
        scrollView.hasVerticalScroller = renderedRows > 9

        for identity in snapshot.hosts {
            let hostContainers = containers.filter { $0.host == identity.key }
            let hostErrors = snapshot.errors.filter { $0.host == identity.key }

            if hostContainers.isEmpty && hostErrors.isEmpty {
                continue
            }

            rowsStack.addArrangedSubview(SegmentHeaderView(title: identity.title))

            for container in hostContainers {
                let row = RowView(isHeader: false)
                row.configure(values: [
                    container.shortID,
                    container.name,
                    container.tag,
                    container.stateDisplay,
                    container.status,
                    container.portsDisplay
                ], state: container.state)
                rowsStack.addArrangedSubview(row)
            }

            for hostError in hostErrors {
                let row = RowView(isHeader: false)
                row.configure(values: [
                    "-",
                    "unavailable",
                    "-",
                    "[ERROR]",
                    hostError.message,
                    "-"
                ], state: "error")
                rowsStack.addArrangedSubview(row)
            }
        }

        resize(for: renderedRows, emptyOrError: false)
    }

    private func renderError(_ error: DockerError) {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        summaryLabel.stringValue = "Docker unavailable"
        rowsStack.addArrangedSubview(EmptyStateView(message: error.message))
        resize(for: 1, emptyOrError: true)
    }

    @objc private func refreshFromButton() {
        refresh()
    }

    @objc private func changeTab() {
        showTab(index: tabControl.selectedSegment)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func iconButton(symbolName: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true

        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.controlSize = .small
        button.toolTip = symbolName == "power" ? "Quit" : "Refresh"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func resize(for rowCount: Int, emptyOrError: Bool) {
        let visibleRows = min(max(rowCount, 1), 9)
        let rowHeight: CGFloat = emptyOrError ? 58 : 30
        let scrollHeight = CGFloat(visibleRows) * rowHeight
        scrollHeightConstraint?.constant = scrollHeight
        if tabControl.selectedSegment == 0 {
            onContentHeightChange?(emptyOrError ? 138 : min(382, 82 + scrollHeight))
        }
    }

    private func showTab(index: Int) {
        containerSection.isHidden = index != 0
        generalSection.isHidden = index != 1
        hostsSection.isHidden = index != 2

        switch index {
        case 1:
            summaryLabel.stringValue = "General"
            syncLaunchAtLoginState()
            onContentHeightChange?(214)
        case 2:
            summaryLabel.stringValue = "\(hostStore.load().count) remote hosts"
            renderHosts()
            onContentHeightChange?(420)
        default:
            refresh()
        }
    }

    private func buildGeneralSection() {
        generalSection.orientation = .vertical
        generalSection.spacing = 14
        generalSection.edgeInsets = NSEdgeInsets(top: 18, left: 12, bottom: 12, right: 12)

        let title = NSTextField(labelWithString: "General")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(toggleLaunchAtLogin)

        let quitButton = NSButton(title: "Quit Bartainer", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded

        let note = NSTextField(wrappingLabelWithString: "Remote host passwords are temporarily stored plainly for testing. Next step: move them to macOS Keychain.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        generalSection.addArrangedSubview(title)
        generalSection.addArrangedSubview(launchAtLoginButton)
        generalSection.addArrangedSubview(note)
        generalSection.addArrangedSubview(quitButton)
    }

    private func buildHostsSection() {
        hostsSection.orientation = .vertical
        hostsSection.spacing = 10
        hostsSection.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)

        hostListStack.orientation = .vertical
        hostListStack.spacing = 6

        let hostScrollView = NSScrollView()
        hostScrollView.drawsBackground = false
        hostScrollView.borderType = .noBorder
        hostScrollView.hasVerticalScroller = true
        hostScrollView.documentView = hostListStack
        hostScrollView.translatesAutoresizingMaskIntoConstraints = false
        hostsSection.addArrangedSubview(hostScrollView)

        NSLayoutConstraint.activate([
            hostScrollView.heightAnchor.constraint(equalToConstant: 176),
            hostListStack.leadingAnchor.constraint(equalTo: hostScrollView.contentView.leadingAnchor),
            hostListStack.trailingAnchor.constraint(equalTo: hostScrollView.contentView.trailingAnchor),
            hostListStack.topAnchor.constraint(equalTo: hostScrollView.contentView.topAnchor),
            hostListStack.widthAnchor.constraint(equalTo: hostScrollView.contentView.widthAnchor)
        ])

        let form = NSGridView(views: [
            [label("Name"), nameField],
            [label("Address"), addressField],
            [label("User"), userField],
            [label("Port"), portField],
            [label("Password"), passwordField]
        ])
        form.column(at: 0).width = 76
        form.rowSpacing = 6
        form.columnSpacing = 10
        hostsSection.addArrangedSubview(form)

        nameField.placeholderString = "home-server"
        addressField.placeholderString = "100.124.170.43"
        userField.placeholderString = NSUserName()
        portField.placeholderString = "22"
        passwordField.placeholderString = "temporary plain password"

        let addButton = NSButton(title: "Add Host", target: self, action: #selector(addHost))
        addButton.bezelStyle = .rounded
        hostsSection.addArrangedSubview(addButton)
    }

    private func renderHosts() {
        hostListStack.arrangedSubviews.forEach { view in
            hostListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let hosts = hostStore.load()
        guard !hosts.isEmpty else {
            let empty = NSTextField(labelWithString: "No remote hosts yet.")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 13)
            hostListStack.addArrangedSubview(empty)
            return
        }

        for index in hosts.indices {
            let row = HostRowView(host: hosts[index], index: index)
            row.onToggle = { [weak self] rowIndex, enabled in
                self?.setHost(rowIndex, enabled: enabled)
            }
            row.onDelete = { [weak self] rowIndex in
                self?.deleteHost(rowIndex)
            }
            hostListStack.addArrangedSubview(row)
        }
    }

    @objc private func addHost() {
        let address = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
        let password = passwordField.stringValue
        var hosts = hostStore.load()

        hosts.append(DockerHost(
            name: name,
            address: address,
            user: user.isEmpty ? NSUserName() : user,
            port: max(port, 1),
            enabled: true,
            password: password.isEmpty ? nil : password
        ))
        hostStore.save(hosts)

        nameField.stringValue = ""
        addressField.stringValue = ""
        userField.stringValue = ""
        portField.stringValue = "22"
        passwordField.stringValue = ""
        showTab(index: 2)
    }

    private func setHost(_ index: Int, enabled: Bool) {
        var hosts = hostStore.load()
        guard hosts.indices.contains(index) else { return }
        hosts[index].enabled = enabled
        hostStore.save(hosts)
        renderHosts()
    }

    private func deleteHost(_ index: Int) {
        var hosts = hostStore.load()
        guard hosts.indices.contains(index) else { return }
        hosts.remove(at: index)
        hostStore.save(hosts)
        showTab(index: 2)
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func syncLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLoginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginButton.isEnabled = false
            launchAtLoginButton.state = .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }

        do {
            if launchAtLoginButton.state == .on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
            summaryLabel.stringValue = "Launch at login failed"
        }
    }
}

final class RowView: NSView {
    private let columnWidths: [CGFloat] = [88, 152, 70, 84, 176, 122]
    private let labels: [CopyableTextField]
    private let isHeader: Bool

    init(isHeader: Bool) {
        self.isHeader = isHeader
        self.labels = columnWidths.map { _ in CopyableTextField(isCopyEnabled: !isHeader) }
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(values: [String], state: String?) {
        for (index, label) in labels.enumerated() {
            let value = index < values.count ? values[index] : ""
            label.stringValue = value
            label.fullValue = value
            label.textColor = color(for: index, state: state)
        }
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = isHeader
            ? NSColor.controlBackgroundColor.withAlphaComponent(0.64).cgColor
            : NSColor.clear.cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: isHeader ? 4 : 6, left: 8, bottom: isHeader ? 3 : 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, label) in labels.enumerated() {
            label.font = isHeader
                ? .monospacedSystemFont(ofSize: 10, weight: .semibold)
                : .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = isHeader ? .secondaryLabelColor : .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalToConstant: columnWidths[index]).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func color(for index: Int, state: String?) -> NSColor {
        guard !isHeader, index == 3 || index == 4, let state else {
            return isHeader ? .secondaryLabelColor : .labelColor
        }

        switch state.lowercased() {
        case "running":
            return NSColor.systemGreen
        case "exited", "dead", "error":
            return NSColor.systemRed
        case "created", "paused", "restarting":
            return NSColor.systemOrange
        default:
            return NSColor.secondaryLabelColor
        }
    }
}

@MainActor
final class CopyableTextField: NSTextField {
    var fullValue = ""
    private let isCopyEnabled: Bool
    private var trackingArea: NSTrackingArea?
    private var hoverTimer: Timer?

    init(isCopyEnabled: Bool) {
        self.isCopyEnabled = isCopyEnabled
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isCopyEnabled, !fullValue.isEmpty, fullValue != "-" else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showTooltip()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        HoverTooltip.shared.hide()
    }

    override func mouseDown(with event: NSEvent) {
        guard isCopyEnabled, !fullValue.isEmpty, fullValue != "-" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullValue, forType: .string)
        HoverTooltip.shared.show(text: "Copied", anchoredTo: self)
    }

    private func showTooltip() {
        guard window != nil else { return }
        HoverTooltip.shared.show(text: fullValue, anchoredTo: self)
    }
}

@MainActor
final class HoverTooltip {
    static let shared = HoverTooltip()
    private let panel: NSPanel
    private let label: NSTextField

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 9
        glass.layer?.masksToBounds = true

        label = NSTextField(wrappingLabelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 8
        label.translatesAutoresizingMaskIntoConstraints = false

        glass.addSubview(label)
        panel.contentView = glass

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: glass.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -8)
        ])
    }

    func show(text: String, anchoredTo view: NSView) {
        label.stringValue = text

        let maxSize = NSSize(width: 460, height: 220)
        let measured = label.cell?.cellSize(forBounds: NSRect(origin: .zero, size: maxSize)) ?? NSSize(width: 220, height: 24)
        let width = min(max(measured.width + 24, 96), maxSize.width)
        let height = min(max(measured.height + 18, 34), maxSize.height)

        guard let window = view.window else { return }
        let cellFrame = view.convert(view.bounds, to: nil)
        let screenFrame = window.convertToScreen(cellFrame)
        let origin = NSPoint(x: screenFrame.minX, y: screenFrame.maxY + 6)

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class SegmentHeaderView: NSView {
    init(title: String) {
        super.init(frame: .zero)
        build(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(title: String) {
        let leftLine = line()
        let rightLine = line()
        let label = NSTextField(labelWithString: title)
        label.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 2, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(leftLine)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(rightLine)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            leftLine.widthAnchor.constraint(equalToConstant: 34),
            rightLine.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func line() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

final class EmptyStateView: NSView {
    init(message: String) {
        super.init(frame: .zero)

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 58),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}

@MainActor
final class HostRowView: NSView {
    var onToggle: ((Int, Bool) -> Void)?
    var onDelete: ((Int) -> Void)?
    private let index: Int
    private let enabledButton: NSButton

    init(host: DockerHost, index: Int) {
        self.index = index
        self.enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        super.init(frame: .zero)
        build(host: host)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(host: DockerHost) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        enabledButton.state = host.enabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(toggle)

        let name = NSTextField(labelWithString: host.displayName)
        name.font = .systemFont(ofSize: 13, weight: .semibold)

        let auth = (host.password?.isEmpty == false) ? "password" : "key"
        let target = NSTextField(labelWithString: "\(host.sshTarget):\(host.port) - \(auth)")
        target.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        target.textColor = .secondaryLabelColor
        target.lineBreakMode = .byTruncatingMiddle

        let deleteImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") ?? NSImage()
        deleteImage.isTemplate = true
        let deleteButton = NSButton(image: deleteImage, target: self, action: #selector(deleteHost))
        deleteButton.isBordered = false
        deleteButton.toolTip = "Delete"

        stack.addArrangedSubview(enabledButton)
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(target)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(deleteButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func toggle() {
        onToggle?(index, enabledButton.state == .on)
    }

    @objc private func deleteHost() {
        onDelete?(index)
    }
}

struct DockerContainer: Decodable, Sendable {
    var host = "local"
    let id: String
    let image: String
    let state: String
    let status: String
    let names: String
    let ports: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case names = "Names"
        case ports = "Ports"
    }

    var shortID: String {
        String(id.prefix(12))
    }

    var name: String {
        names.split(separator: ",").first.map(String.init) ?? names
    }

    var tag: String {
        let imageName = image.split(separator: "/").last.map(String.init) ?? image
        guard let colonIndex = imageName.lastIndex(of: ":") else {
            return "latest"
        }
        return String(imageName[imageName.index(after: colonIndex)...])
    }

    var stateDisplay: String {
        "[\(state.uppercased())]"
    }

    var portsDisplay: String {
        let clean = ports.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "-" }

        let entries = clean
            .split(separator: ",")
            .map { normalize(port: String($0)) }
            .reduce(into: [String]()) { result, entry in
                if !result.contains(entry) {
                    result.append(entry)
                }
            }

        return entries.joined(separator: "\n")
    }

    private func normalize(port: String) -> String {
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)

        if let arrowRange = trimmed.range(of: "->") {
            let publicSide = String(trimmed[..<arrowRange.lowerBound])
            let privateSide = String(trimmed[arrowRange.upperBound...])
            let publicPort = publicSide.split(separator: ":").last.map(String.init) ?? publicSide
            let parts = privateSide.split(separator: "/", maxSplits: 1).map(String.init)

            if parts.count == 2 {
                return "\(publicPort) -> \(parts[0]) / \(parts[1])"
            }

            return "\(publicPort) -> \(privateSide)"
        }

        let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return "\(parts[0]) / \(parts[1])"
        }

        return trimmed
    }
}

struct DockerSnapshot: Sendable {
    let containers: [DockerContainer]
    let errors: [HostError]
    let hosts: [HostIdentity]
}

struct HostError: Sendable {
    let host: String
    let message: String
}

struct HostIdentity: Sendable, Equatable {
    let key: String
    let title: String
}

struct HostCommandError: Error, Sendable {
    let message: String
}

struct DockerHost: Codable, Sendable, Equatable {
    var name: String
    var address: String
    var user: String
    var port: Int
    var enabled: Bool
    var password: String?

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? address : name
    }

    var sshTarget: String {
        let cleanUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanUser.isEmpty ? address : "\(cleanUser)@\(address)"
    }

    var segmentTitle: String {
        sshTarget
    }
}

final class HostStore {
    private let key = "bartainer.remoteHosts"

    func load() -> [DockerHost] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hosts = try? JSONDecoder().decode([DockerHost].self, from: data) else {
            return []
        }

        return hosts
    }

    func save(_ hosts: [DockerHost]) {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum DockerError: Error, Sendable {
    case dockerNotFound
    case commandFailed(String)
    case parseFailed

    var message: String {
        switch self {
        case .dockerNotFound:
            return "Could not find the Docker CLI. Install Docker Desktop or make sure docker is available in /usr/local/bin, /opt/homebrew/bin, or /usr/bin."
        case .commandFailed(let output):
            return output.isEmpty ? "Docker did not return container data. Make sure Docker Desktop is running." : output
        case .parseFailed:
            return "Docker returned data, but Bartainer could not parse it."
        }
    }
}

final class DockerService: @unchecked Sendable {
    func listContainers(hosts: [DockerHost], completion: @escaping @Sendable (Result<DockerSnapshot, DockerError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var containers: [DockerContainer] = []
            var errors: [HostError] = []
            var identities: [HostIdentity] = [HostIdentity(key: "local", title: self.localHostTitle())]

            switch self.runDocker(host: "local", executable: self.findDockerPath(), arguments: ["ps", "-a", "--format", "{{json .}}"], password: nil) {
            case .success(let localContainers):
                containers.append(contentsOf: localContainers)
            case .failure(let error):
                errors.append(HostError(host: "local", message: error.message))
            }

            for host in hosts where host.enabled {
                identities.append(HostIdentity(key: host.displayName, title: host.segmentTitle))
                guard let sshPath = self.findSSHPath() else {
                    errors.append(HostError(host: host.displayName, message: "SSH command not found."))
                    continue
                }

                let remoteCommand = "docker ps -a --format '{{json .}}'"
                var arguments = [
                    "-o", "ConnectTimeout=5",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-p", "\(host.port)"
                ]

                if host.password?.isEmpty != false {
                    arguments.append(contentsOf: ["-o", "BatchMode=yes"])
                }

                arguments.append(contentsOf: [host.sshTarget, remoteCommand])

                switch self.runDocker(host: host.displayName, executable: sshPath, arguments: arguments, password: host.password) {
                case .success(let remoteContainers):
                    containers.append(contentsOf: remoteContainers)
                case .failure(let error):
                    errors.append(HostError(host: host.displayName, message: error.message))
                }
            }

            if containers.isEmpty && errors.count == 1 && errors.first?.host == "local" && hosts.filter(\.enabled).isEmpty {
                completion(.failure(.commandFailed(errors[0].message)))
                return
            }

            completion(.success(DockerSnapshot(containers: containers, errors: errors, hosts: identities)))
        }
    }

    private func runDocker(host: String, executable: String?, arguments: [String], password: String?) -> Result<[DockerContainer], HostCommandError> {
        guard let executable else {
            return .failure(HostCommandError(message: "Command not found."))
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let askPassURL: URL?

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        if let password, !password.isEmpty {
            do {
                askPassURL = try makeAskPassScript()
                environment["SSH_ASKPASS"] = askPassURL?.path
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["DISPLAY"] = "bartainer:0"
                environment["BARTAINER_SSH_PASSWORD"] = password
            } catch {
                return .failure(HostCommandError(message: "Could not prepare temporary SSH password helper."))
            }
        } else {
            askPassURL = nil
        }

        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            cleanupAskPassScript(askPassURL)
            return .failure(HostCommandError(message: error.localizedDescription))
        }

        cleanupAskPassScript(askPassURL)

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let cleanError = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(HostCommandError(message: cleanError.isEmpty ? "Command failed." : cleanError))
        }

        var parseFailed = false
        let containers = output
            .split(separator: "\n")
            .compactMap { line -> DockerContainer? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                guard var container = try? JSONDecoder().decode(DockerContainer.self, from: data) else {
                    parseFailed = true
                    return nil
                }
                container.host = host
                return container
            }

        if parseFailed {
            return .failure(HostCommandError(message: "Docker returned data, but Bartainer could not parse it."))
        }

        return .success(containers)
    }

    private func makeAskPassScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("bartainer-askpass-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$BARTAINER_SSH_PASSWORD\"\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func cleanupAskPassScript(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func findSSHPath() -> String? {
        let candidates = [
            "/usr/bin/ssh",
            "/opt/homebrew/bin/ssh",
            "/usr/local/bin/ssh"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func localHostTitle() -> String {
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "\(NSUserName())@\(hostName)"
    }

    private func findDockerPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/usr/bin/docker"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

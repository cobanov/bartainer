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
    private let contentStack = NSStackView()
    private let containerSection = NSStackView()
    private let scrollView = NSScrollView()
    private let rowsStack = FlippedStackView()
    private let summaryLabel = NSTextField(labelWithString: "Loading containers...")
    private let spinner = NSProgressIndicator()
    private var scrollHeightConstraint: NSLayoutConstraint?
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

        summaryLabel.font = .systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let refreshButton = iconButton(symbolName: "arrow.clockwise", action: #selector(refreshFromButton))
        let settingsButton = iconButton(symbolName: "gearshape", action: #selector(openSettings))
        let quitButton = iconButton(symbolName: "power", action: #selector(quit))

        toolbar.addArrangedSubview(title)
        toolbar.addArrangedSubview(summaryLabel)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(spinner)
        toolbar.addArrangedSubview(refreshButton)
        toolbar.addArrangedSubview(settingsButton)
        toolbar.addArrangedSubview(quitButton)

        return toolbar
    }

    private func headerRow() -> NSView {
        let row = RowView(isHeader: true, rowIndex: 0)
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

        var globalRowIndex = 0
        for identity in snapshot.hosts {
            let hostContainers = containers.filter { $0.host == identity.key }
            let hostErrors = snapshot.errors.filter { $0.host == identity.key }

            if hostContainers.isEmpty && hostErrors.isEmpty {
                continue
            }

            rowsStack.addArrangedSubview(SegmentHeaderView(title: identity.title))

            for container in hostContainers {
                let row = RowView(isHeader: false, rowIndex: globalRowIndex)
                row.configure(values: [
                    container.shortID,
                    container.name,
                    container.tag,
                    container.stateDisplay,
                    container.status,
                    container.portsDisplay
                ], state: container.state)
                rowsStack.addArrangedSubview(row)
                globalRowIndex += 1
            }

            for hostError in hostErrors {
                let row = RowView(isHeader: false, rowIndex: globalRowIndex)
                row.configure(values: [
                    "-",
                    "unavailable",
                    "-",
                    "ERROR",
                    hostError.message,
                    "-"
                ], state: "error")
                rowsStack.addArrangedSubview(row)
                globalRowIndex += 1
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(hostStore: hostStore) { [weak self] in
            self?.refresh()
        }
    }

    private func iconButton(symbolName: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true

        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.controlSize = .small
        button.toolTip = symbolName == "power" ? "Quit" : (symbolName == "gearshape" ? "Settings" : "Refresh")
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
        onContentHeightChange?(emptyOrError ? 138 : min(382, 82 + scrollHeight))
    }
}

final class RowView: NSView {
    private let columnWidths: [CGFloat] = [88, 152, 70, 84, 176, 122]
    private let labels: [CopyableTextField]
    private let isHeader: Bool
    private let rowIndex: Int
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(isHeader: Bool, rowIndex: Int) {
        self.isHeader = isHeader
        self.rowIndex = rowIndex
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
        updateBackground()

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

    private func updateBackground() {
        guard !isHeader else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.64).cgColor
            return
        }
        if isHovered {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else if rowIndex % 2 == 1 {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.22).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        guard !isHeader else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
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
    private weak var parentWindow: NSWindow?

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
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

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
        let origin = adjustedOrigin(
            preferred: NSPoint(x: screenFrame.minX, y: screenFrame.maxY + 8),
            size: NSSize(width: width, height: height),
            screen: window.screen
        )

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)

        if parentWindow !== window {
            parentWindow?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            parentWindow = window
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        parentWindow?.removeChildWindow(panel)
        parentWindow = nil
        panel.orderOut(nil)
    }

    private func adjustedOrigin(preferred: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        guard let visibleFrame = screen?.visibleFrame else {
            return preferred
        }

        var origin = preferred
        if origin.x + size.width > visibleFrame.maxX - 8 {
            origin.x = visibleFrame.maxX - size.width - 8
        }
        if origin.x < visibleFrame.minX + 8 {
            origin.x = visibleFrame.minX + 8
        }
        if origin.y + size.height > visibleFrame.maxY - 8 {
            origin.y = preferred.y - size.height - 42
        }
        if origin.y < visibleFrame.minY + 8 {
            origin.y = visibleFrame.minY + 8
        }
        return origin
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
    override var isFlipped: Bool { true }
}

// MARK: - Settings Window

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var settingsViewController: SettingsViewController?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Bartainer Settings"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(hostStore: HostStore, onChange: @escaping () -> Void) {
        let controller = SettingsViewController(hostStore: hostStore, onChange: onChange)
        settingsViewController = controller
        window?.contentViewController = controller
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SettingsViewController: NSViewController {
    private enum Section { case general, hosts, about }

    private let hostStore: HostStore
    private let onChange: () -> Void

    private let generalButton = SettingsSidebarButton(title: "General", symbolName: "gearshape.fill")
    private let hostsButton = SettingsSidebarButton(title: "Hosts", symbolName: "server.rack")
    private let aboutButton = SettingsSidebarButton(title: "About", symbolName: "info.circle.fill")

    private let generalSection = NSStackView()
    private let hostsSection = NSStackView()
    private let aboutSection = NSStackView()

    private let hostListStack = FlippedStackView()
    private let launchAtLoginToggle = NSSwitch()
    private let nameField = NSTextField()
    private let addressField = NSTextField()
    private let userField = NSTextField()
    private let portField = NSTextField(string: "22")
    private let passwordField = NSSecureTextField()
    private let formTitleLabel = NSTextField(labelWithString: "Add Remote Host")
    private let saveHostButton = NSButton(title: "Add Host", target: nil, action: nil)
    private let cancelEditButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let removeHostButton = NSButton(title: "Remove", target: nil, action: nil)
    private var editingHostIndex: Int?

    init(hostStore: HostStore, onChange: @escaping () -> Void) {
        self.hostStore = hostStore
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 760, height: 530))
        glass.material = .windowBackground
        glass.blendingMode = .behindWindow
        glass.state = .active
        view = glass
        buildView()
        select(.general)
    }

    private func buildView() {
        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        root.addArrangedSubview(sidebar())

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        root.addArrangedSubview(divider)

        let content = NSScrollView()
        content.drawsBackground = false
        content.borderType = .noBorder
        content.hasVerticalScroller = false

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 0
        contentStack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        buildGeneralSection()
        buildHostsSection()
        buildAboutSection()
        contentStack.addArrangedSubview(generalSection)
        contentStack.addArrangedSubview(hostsSection)
        contentStack.addArrangedSubview(aboutSection)

        content.documentView = contentStack
        content.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: content.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: content.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: content.contentView.topAnchor),
            contentStack.widthAnchor.constraint(equalTo: content.contentView.widthAnchor)
        ])

        root.addArrangedSubview(content)
    }

    private func sidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 210).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 52, left: 12, bottom: 20, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor)
        ])

        generalButton.target = self
        generalButton.action = #selector(selectGeneral)
        hostsButton.target = self
        hostsButton.action = #selector(selectHosts)
        aboutButton.target = self
        aboutButton.action = #selector(selectAbout)

        stack.addArrangedSubview(generalButton)
        stack.addArrangedSubview(sidebarSectionLabel("Settings"))
        stack.addArrangedSubview(hostsButton)
        stack.addArrangedSubview(sidebarSectionLabel("Bartainer"))
        stack.addArrangedSubview(aboutButton)
        stack.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            generalButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 4),
            generalButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -4),
            hostsButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 4),
            hostsButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -4),
            aboutButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 4),
            aboutButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -4)
        ])

        return sidebar
    }

    private func buildGeneralSection() {
        generalSection.orientation = .vertical
        generalSection.spacing = 16
        generalSection.addArrangedSubview(pageTitle("General", symbolName: "gearshape.fill"))

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(toggleLaunchAtLogin)

        let quitButton = NSButton(title: "Quit Bartainer", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .regular

        let card = settingsCard()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        stack.addArrangedSubview(settingRow(title: "Launch at login", subtitle: "Start Bartainer automatically on login", control: launchAtLoginToggle))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(settingRow(title: "Quit Bartainer", subtitle: "Close the app and remove the menu bar icon", control: quitButton))

        let note = infoNote("Remote host passwords are temporarily stored in plain text. They will be moved to the macOS Keychain in a future update.")

        generalSection.addArrangedSubview(card)
        generalSection.addArrangedSubview(note)
        generalSection.addArrangedSubview(NSView())
    }

    private func buildHostsSection() {
        hostsSection.orientation = .vertical
        hostsSection.spacing = 16
        hostsSection.addArrangedSubview(pageTitle("Hosts", symbolName: "server.rack"))

        // Host list card
        let listCard = settingsCard()
        let listCardStack = NSStackView()
        listCardStack.orientation = .vertical
        listCardStack.spacing = 0
        listCardStack.translatesAutoresizingMaskIntoConstraints = false
        listCard.addSubview(listCardStack)
        NSLayoutConstraint.activate([
            listCardStack.leadingAnchor.constraint(equalTo: listCard.leadingAnchor),
            listCardStack.trailingAnchor.constraint(equalTo: listCard.trailingAnchor),
            listCardStack.topAnchor.constraint(equalTo: listCard.topAnchor),
            listCardStack.bottomAnchor.constraint(equalTo: listCard.bottomAnchor)
        ])

        // List header
        let listHeader = NSStackView()
        listHeader.orientation = .horizontal
        listHeader.alignment = .centerY
        listHeader.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 12)
        let listTitle = NSTextField(labelWithString: "Remote Hosts")
        listTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let addNewButton = NSButton(title: "+ Add New", target: self, action: #selector(startNewHost))
        addNewButton.bezelStyle = .rounded
        addNewButton.controlSize = .small
        addNewButton.font = .systemFont(ofSize: 12)
        listHeader.addArrangedSubview(listTitle)
        listHeader.addArrangedSubview(NSView())
        listHeader.addArrangedSubview(addNewButton)
        listCardStack.addArrangedSubview(listHeader)
        listCardStack.addArrangedSubview(separator())

        hostListStack.orientation = .vertical
        hostListStack.spacing = 0

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = hostListStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listCardStack.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 170),
            hostListStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostListStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostListStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostListStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        hostsSection.addArrangedSubview(listCard)

        // Form card
        let formCard = settingsCard()
        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.spacing = 10
        formStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        formStack.translatesAutoresizingMaskIntoConstraints = false
        formCard.addSubview(formStack)
        NSLayoutConstraint.activate([
            formStack.leadingAnchor.constraint(equalTo: formCard.leadingAnchor),
            formStack.trailingAnchor.constraint(equalTo: formCard.trailingAnchor),
            formStack.topAnchor.constraint(equalTo: formCard.topAnchor),
            formStack.bottomAnchor.constraint(equalTo: formCard.bottomAnchor)
        ])

        formTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        formStack.addArrangedSubview(formTitleLabel)

        let grid = NSGridView(views: [
            [formLabel("Name"), nameField],
            [formLabel("Address"), addressField],
            [formLabel("User"), userField],
            [formLabel("Port"), portField],
            [formLabel("Password"), passwordField]
        ])
        grid.column(at: 0).width = 72
        grid.rowSpacing = 6
        grid.columnSpacing = 10
        formStack.addArrangedSubview(grid)

        nameField.placeholderString = "home-server"
        nameField.font = .systemFont(ofSize: 13)
        addressField.placeholderString = "192.168.1.100"
        addressField.font = .systemFont(ofSize: 13)
        userField.placeholderString = NSUserName()
        userField.font = .systemFont(ofSize: 13)
        portField.placeholderString = "22"
        portField.font = .systemFont(ofSize: 13)
        passwordField.placeholderString = "temporary plain text (will move to Keychain)"
        passwordField.font = .systemFont(ofSize: 13)

        saveHostButton.target = self
        saveHostButton.action = #selector(saveHost)
        saveHostButton.bezelStyle = .rounded
        saveHostButton.keyEquivalent = "\r"

        cancelEditButton.target = self
        cancelEditButton.action = #selector(cancelHostEdit)
        cancelEditButton.bezelStyle = .rounded

        removeHostButton.target = self
        removeHostButton.action = #selector(removeSelectedHost)
        removeHostButton.bezelStyle = .rounded
        removeHostButton.contentTintColor = .systemRed

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        actionRow.addArrangedSubview(saveHostButton)
        actionRow.addArrangedSubview(cancelEditButton)
        actionRow.addArrangedSubview(removeHostButton)
        actionRow.addArrangedSubview(NSView())
        formStack.addArrangedSubview(actionRow)

        hostsSection.addArrangedSubview(formCard)
        hostsSection.addArrangedSubview(NSView())
        resetHostForm()
    }

    private func buildAboutSection() {
        aboutSection.orientation = .vertical
        aboutSection.spacing = 16
        aboutSection.addArrangedSubview(pageTitle("About", symbolName: "info.circle.fill"))

        let card = settingsCard()
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 12
        cardStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        let appName = NSTextField(labelWithString: "Bartainer")
        appName.font = .systemFont(ofSize: 18, weight: .semibold)

        let desc = NSTextField(wrappingLabelWithString: "A compact macOS menu bar app for viewing local and remote Docker containers at a glance.")
        desc.font = .systemFont(ofSize: 13)
        desc.textColor = .secondaryLabelColor

        let repoRow = NSStackView()
        repoRow.orientation = .horizontal
        repoRow.spacing = 6
        let repoIcon = NSImageView(image: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage())
        repoIcon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        repoIcon.contentTintColor = .secondaryLabelColor
        repoIcon.translatesAutoresizingMaskIntoConstraints = false
        repoIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let repoLabel = NSTextField(labelWithString: "github.com/cobanov/bartainer")
        repoLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        repoLabel.textColor = .secondaryLabelColor
        repoRow.addArrangedSubview(repoIcon)
        repoRow.addArrangedSubview(repoLabel)

        cardStack.addArrangedSubview(appName)
        cardStack.addArrangedSubview(desc)
        cardStack.addArrangedSubview(repoRow)

        aboutSection.addArrangedSubview(card)
        aboutSection.addArrangedSubview(NSView())
    }

    private func renderHosts() {
        hostListStack.arrangedSubviews.forEach { v in
            hostListStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        let hosts = hostStore.load()
        guard !hosts.isEmpty else {
            let emptyStack = NSStackView()
            emptyStack.orientation = .vertical
            emptyStack.alignment = .centerX
            emptyStack.edgeInsets = NSEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)
            let empty = NSTextField(labelWithString: "No remote hosts added yet.")
            empty.textColor = .tertiaryLabelColor
            empty.font = .systemFont(ofSize: 13)
            emptyStack.addArrangedSubview(empty)
            hostListStack.addArrangedSubview(emptyStack)
            return
        }

        for index in hosts.indices {
            let row = HostRowView(host: hosts[index], index: index, isSelected: editingHostIndex == index)
            row.onToggle = { [weak self] idx, enabled in self?.setHost(idx, enabled: enabled) }
            row.onDelete = { [weak self] idx in self?.deleteHost(idx) }
            row.onSelect = { [weak self] idx in self?.editHost(idx) }
            hostListStack.addArrangedSubview(row)
            if index < hosts.count - 1 {
                hostListStack.addArrangedSubview(rowSeparator())
            }
        }
    }

    @objc private func selectGeneral() { select(.general) }
    @objc private func selectHosts() { select(.hosts) }
    @objc private func selectAbout() { select(.about) }

    private func select(_ section: Section) {
        generalSection.isHidden = section != .general
        hostsSection.isHidden = section != .hosts
        aboutSection.isHidden = section != .about
        generalButton.isSelected = section == .general
        hostsButton.isSelected = section == .hosts
        aboutButton.isSelected = section == .about
        if section == .general { syncLaunchAtLoginState() }
        if section == .hosts { renderHosts() }
    }

    @objc private func startNewHost() {
        resetHostForm()
        renderHosts()
    }

    @objc private func saveHost() {
        let address = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
        let password = passwordField.stringValue
        var hosts = hostStore.load()

        let host = DockerHost(
            name: name,
            address: address,
            user: user.isEmpty ? NSUserName() : user,
            port: max(port, 1),
            enabled: true,
            password: password.isEmpty ? nil : password
        )

        if let editingHostIndex, hosts.indices.contains(editingHostIndex) {
            var updated = host
            updated.enabled = hosts[editingHostIndex].enabled
            hosts[editingHostIndex] = updated
        } else {
            hosts.append(host)
        }

        hostStore.save(hosts)
        resetHostForm()
        renderHosts()
        onChange()
    }

    @objc private func cancelHostEdit() {
        resetHostForm()
        renderHosts()
    }

    @objc private func removeSelectedHost() {
        guard let editingHostIndex else { return }
        deleteHost(editingHostIndex)
    }

    private func editHost(_ index: Int) {
        let hosts = hostStore.load()
        guard hosts.indices.contains(index) else { return }
        let host = hosts[index]
        editingHostIndex = index
        formTitleLabel.stringValue = "Edit Host — \(host.displayName)"
        saveHostButton.title = "Save Changes"
        cancelEditButton.isHidden = false
        removeHostButton.isHidden = false
        nameField.stringValue = host.name
        addressField.stringValue = host.address
        userField.stringValue = host.user
        portField.stringValue = "\(host.port)"
        passwordField.stringValue = host.password ?? ""
        renderHosts()
    }

    private func resetHostForm() {
        editingHostIndex = nil
        formTitleLabel.stringValue = "Add Remote Host"
        saveHostButton.title = "Add Host"
        cancelEditButton.isHidden = true
        removeHostButton.isHidden = true
        nameField.stringValue = ""
        addressField.stringValue = ""
        userField.stringValue = ""
        portField.stringValue = "22"
        passwordField.stringValue = ""
    }

    private func setHost(_ index: Int, enabled: Bool) {
        var hosts = hostStore.load()
        guard hosts.indices.contains(index) else { return }
        hosts[index].enabled = enabled
        hostStore.save(hosts)
        renderHosts()
        onChange()
    }

    private func deleteHost(_ index: Int) {
        var hosts = hostStore.load()
        guard hosts.indices.contains(index) else { return }
        hosts.remove(at: index)
        hostStore.save(hosts)
        resetHostForm()
        renderHosts()
        onChange()
    }

    private func syncLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLoginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginToggle.isEnabled = false
            launchAtLoginToggle.state = .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLoginToggle.state == .on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func pageTitle(_ title: String, symbolName: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage()
        image.isTemplate = true
        let icon = NSImageView(image: image)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 20, weight: .semibold)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(NSView())
        return stack
    }

    private func settingRow(title: String, subtitle: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .tertiaryLabelColor

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(control)
        return row
    }

    private func settingsCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        return card
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func rowSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func formLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    private func infoNote(_ text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor

        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        return row
    }

    private func sidebarSectionLabel(_ text: String) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -2),
            wrapper.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])

        return wrapper
    }
}

@MainActor
final class SettingsSidebarButton: NSButton {
    var isSelected: Bool = false {
        didSet { updateStyle() }
    }

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage()
        image.isTemplate = true
        self.title = "  \(title)"
        self.image = image
        imagePosition = .imageLeading
        alignment = .left
        isBordered = false
        font = .systemFont(ofSize: 13.5, weight: .regular)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateStyle() {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
        font = .systemFont(ofSize: 13.5, weight: isSelected ? .semibold : .regular)
        contentTintColor = isSelected ? .controlAccentColor : .labelColor
    }
}

@MainActor
final class HostRowView: NSView {
    var onToggle: ((Int, Bool) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    private let index: Int
    private let isSelected: Bool
    private var host: DockerHost
    private let statusDot = NSView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(host: DockerHost, index: Int, isSelected: Bool) {
        self.index = index
        self.isSelected = isSelected
        self.host = host
        super.init(frame: .zero)
        build(host: host)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(host: DockerHost) {
        wantsLayer = true
        updateBackground()

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Status dot (clickable to toggle)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = dotColor(for: host.enabled).cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        let dotButton = NSButton(frame: .zero)
        dotButton.isBordered = false
        dotButton.bezelStyle = .regularSquare
        dotButton.target = self
        dotButton.action = #selector(toggleEnabled)
        dotButton.wantsLayer = true
        dotButton.layer?.backgroundColor = NSColor.clear.cgColor
        dotButton.translatesAutoresizingMaskIntoConstraints = false
        dotButton.addSubview(statusDot)
        NSLayoutConstraint.activate([
            dotButton.widthAnchor.constraint(equalToConstant: 20),
            dotButton.heightAnchor.constraint(equalToConstant: 20),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            statusDot.centerXAnchor.constraint(equalTo: dotButton.centerXAnchor),
            statusDot.centerYAnchor.constraint(equalTo: dotButton.centerYAnchor)
        ])

        // Text
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading

        let name = NSTextField(labelWithString: host.displayName)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail

        let auth = (host.password?.isEmpty == false) ? "password" : "key"
        let detail = NSTextField(labelWithString: "\(host.sshTarget):\(host.port) · \(auth)")
        detail.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle

        textStack.addArrangedSubview(name)
        textStack.addArrangedSubview(detail)

        // Delete button
        let deleteBtn = makeActionButton(symbolName: "trash", tooltip: "Remove Host")
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteHost)
        deleteBtn.contentTintColor = .systemRed

        stack.addArrangedSubview(dotButton)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(deleteBtn)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeActionButton(symbolName: String, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) ?? NSImage()
        image.isTemplate = true
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.toolTip = tooltip
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func dotColor(for enabled: Bool) -> NSColor {
        enabled ? .systemGreen : .tertiaryLabelColor
    }

    private func updateBackground() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    @objc private func toggleEnabled() {
        onToggle?(index, !host.enabled)
    }

    @objc private func deleteHost() {
        onDelete?(index)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }
}

// MARK: - Docker Data Models

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
        state.uppercased()
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

// MARK: - Docker Service

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
        let candidates = ["/usr/bin/ssh", "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func localHostTitle() -> String {
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "\(NSUserName())@\(hostName)"
    }

    private func findDockerPath() -> String? {
        let candidates = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "/usr/bin/docker"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

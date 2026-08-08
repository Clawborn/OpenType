import AppKit
import Combine
import SwiftUI

@main
struct OpenTypeApp: App {
    @NSApplicationDelegateAdaptor(OpenTypeAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class OpenTypeAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        observeStatusPresentation()

        model.start()
        model.refreshPermissionStatus()
        didFinishLaunching = true

        // Opening the app should produce visible feedback even though OpenType
        // is an accessory app with no Dock window.
        DispatchQueue.main.async { [weak self] in
            self?.showPopover()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // macOS 26 does not consistently call applicationShouldHandleReopen
        // for LSUIElement apps. Reopening OpenType does make it active, so this
        // is the reliable path for presenting its only user-facing window.
        guard didFinishLaunching else { return }
        showPopover()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPopover()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    private func configureStatusItem() {
        let autosaveName = "OpenType"
        let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: preferredPositionKey) == nil {
            // Lower values stay closer to the system controls on the right.
            // This keeps OpenType out from under the MacBook camera housing on
            // first launch while preserving any later Command-drag position.
            UserDefaults.standard.set(260, forKey: preferredPositionKey)
        }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        item.autosaveName = autosaveName
        item.isVisible = true

        guard let button = item.button else {
            statusItem = item
            return
        }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.toolTip = "OpenType"
        button.setAccessibilityLabel("OpenType")
        statusItem = item
        updateStatusIcon(
            for: model.state,
            colorTheme: model.configuration.colorTheme
        )
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 424, height: 568)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: RootView(model: model)
        )
    }

    private func observeStatusPresentation() {
        Publishers.CombineLatest(
            model.$state.removeDuplicates(),
            model.configuration.$colorTheme.removeDuplicates()
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] state, colorTheme in
                self?.updateStatusIcon(for: state, colorTheme: colorTheme)
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(
        for state: ProcessingState,
        colorTheme: AppColorTheme
    ) {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarStatusIcon.image(
            for: state,
            colorTheme: colorTheme
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}

enum MenuBarStatusIcon {
    static func image(
        for state: ProcessingState,
        colorTheme: AppColorTheme = .ocean
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let pixelWidth = 36
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelWidth,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return NSImage(size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        drawPixels(for: state, colorTheme: colorTheme)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        image.isTemplate = false
        image.accessibilityDescription = "OpenType"
        return image
    }

    private static func drawPixels(
        for state: ProcessingState,
        colorTheme: AppColorTheme
    ) {
        let rect = NSRect(x: 0, y: 0, width: 36, height: 36)
        backgroundColor(for: state, colorTheme: colorTheme).setFill()
        NSBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1),
            xRadius: 10,
            yRadius: 10
        ).fill()

        NSColor.white.setFill()
        let heights: [CGFloat] = [12, 22, 30, 20, 12]
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2.8
        let totalWidth = CGFloat(heights.count) * barWidth
            + CGFloat(heights.count - 1) * gap
        let startX = rect.midX - totalWidth / 2

        for (index, height) in heights.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + gap)
            let bar = NSRect(
                x: x,
                y: rect.midY - height / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(
                roundedRect: bar,
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
        }
    }

    private static func backgroundColor(
        for state: ProcessingState,
        colorTheme: AppColorTheme
    ) -> NSColor {
        switch state {
        case .listening:
            return .systemRed
        case .transcribing, .transforming, .inserting:
            return .systemPurple
        case .failure:
            return .systemOrange
        default:
            return colorTheme.nsAccent
        }
    }
}

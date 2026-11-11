import AppKit
import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(CollegeApplicationsAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CollegeApplicationsAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var hostingController: NSHostingController<ContentView>?
    private var canReleaseContent = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeDismissalMonitors()
    }

    func popoverWillShow(_ notification: Notification) {
        configureDismissalMonitors()
    }

    func popoverDidShow(_ notification: Notification) {
        // A menu-bar popover can be visible without the app being active.
        hostingController?.rootView.isPopoverActive = true
    }

    func popoverWillClose(_ notification: Notification) {
        // Remove the repeating animation even when the view is retained.
        hostingController?.rootView.isPopoverActive = false
    }

    func popoverDidClose(_ notification: Notification) {
        hostingController?.rootView.isPopoverActive = false
        removeDismissalMonitors()

        // Keep an editor or detail screen intact, including unsaved form state.
        // The idle list can be rebuilt from persisted data on the next opening.
        if canReleaseContent {
            popover.contentViewController = nil
            hostingController = nil
            canReleaseContent = false
        }
    }

    private func removeDismissalMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "CollegeApplications.StatusItem"

        guard let button = statusItem.button else { return }

        let image = NSImage(
            systemSymbolName: "graduationcap.fill",
            accessibilityDescription: "College Applications"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "College Applications"
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
    }

    private var availableContentHeight: CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        return max(220, (screen?.visibleFrame.height ?? 720) - 4)
    }

    private func configureDismissalMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        let mouseEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mouseEvents
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }

            let popoverWindow = self.popover.contentViewController?.view.window
            let statusItemWindow = self.statusItem.button?.window
            if !self.isPopoverInteractionWindow(
                event.window,
                popoverWindow: popoverWindow,
                statusItemWindow: statusItemWindow
            ) {
                self.popover.performClose(nil)
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mouseEvents
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover.performClose(nil)
            }
        }
    }

    private func isPopoverInteractionWindow(
        _ window: NSWindow?,
        popoverWindow: NSWindow?,
        statusItemWindow: NSWindow?
    ) -> Bool {
        guard let window else { return false }

        if window === popoverWindow || window === statusItemWindow {
            return true
        }

        // SwiftUI controls such as graphical DatePicker present their controls
        // in an auxiliary AppKit panel outside the popover's window.
        if window is NSPanel {
            return true
        }

        var parentWindow = window.parent
        while let parent = parentWindow {
            if parent === popoverWindow {
                return true
            }
            parentWindow = parent.parent
        }

        return false
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            let content = ContentView(
                maximumListHeight: availableContentHeight,
                onReleaseEligibilityChange: { [weak self] canRelease in
                    self?.canReleaseContent = canRelease
                }
            )
            if let hostingController {
                hostingController.rootView = content
            } else {
                let controller = NSHostingController(rootView: content)
                controller.sizingOptions = [.preferredContentSize]
                hostingController = controller
                popover.contentViewController = controller
            }
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            NSApp.activate()
        }
    }
}

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
final class CollegeApplicationsAppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
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
        let hostingController = NSHostingController(rootView: ContentView())
        hostingController.sizingOptions = [.preferredContentSize]

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
}

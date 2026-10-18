import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        MenuBarExtra("College Applications", systemImage: "graduationcap.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

import Cocoa

// Single-instance guard: if another BGMMR is already running, bring it
// forward and exit so we never end up with two menu-bar items / panels.
if let me = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: me)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let existing = others.first {
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar agent app, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()

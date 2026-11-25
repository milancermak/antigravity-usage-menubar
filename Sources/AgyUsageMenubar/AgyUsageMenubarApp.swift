import AppKit

@main
@MainActor
final class AgyUsageMenubarApp: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel?
    private var statusBarController: StatusBarController?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AgyUsageMenubarApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = UsageViewModel()
        let controller = StatusBarController(viewModel: vm)
        self.viewModel = vm
        self.statusBarController = controller
        vm.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }
}

import AppKit
import ChargeWattCore
import Foundation

@MainActor
private var retainedDelegate: ChargeWattMenuDelegate?

@main
struct ChargeWattMenuApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ChargeWattMenuDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

private actor BatterySnapshotReaderActor {
    private let reader = BatteryPowerReader()

    func readSnapshot() -> BatterySnapshot {
        reader.readSnapshot()
    }
}

@MainActor
final class ChargeWattMenuDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let snapshotReader = BatterySnapshotReaderActor()
    private let formatter = PowerFormatter()
    private let menu = NSMenu()
    private let detailItems = (0 ..< 8).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let updatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var snapshot = BatterySnapshot.unavailable()
    private var refreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        refresh()
        startTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.title = "--W"
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        button.toolTip = "当前电池侧功率"
    }

    private func configureMenu() {
        menu.delegate = self

        for item in detailItems {
            item.isEnabled = false
            menu.addItem(item)
        }

        updatedItem.isEnabled = false
        menu.addItem(updatedItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "立即刷新",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出充电功率",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        statusItem.menu = menu
    }

    private func startTimer() {
        let timer = Timer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    @objc private func timerFired() {
        refresh()
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            let snapshot = await snapshotReader.readSnapshot()
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self.applySnapshot(snapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: BatterySnapshot) {
        self.snapshot = snapshot
        statusItem.button?.title = formatter.statusTitle(for: snapshot)
        statusItem.button?.toolTip = formatter.menuLines(for: snapshot).first
        updateMenuItems()
    }

    private func updateMenuItems() {
        let lines = formatter.menuLines(for: snapshot)
        for (index, item) in detailItems.enumerated() {
            let title = index < lines.count ? lines[index] : ""
            setInformationTitle(item, title)
            item.isHidden = item.title.isEmpty
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .medium
        setInformationTitle(
            updatedItem,
            "更新时间：\(dateFormatter.string(from: snapshot.date))"
        )
    }

    private func setInformationTitle(_ item: NSMenuItem, _ title: String) {
        item.title = title
        item.isEnabled = false
    }
}

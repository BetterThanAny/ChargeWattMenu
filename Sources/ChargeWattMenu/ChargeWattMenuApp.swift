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

@MainActor
final class ChargeWattMenuDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = BatteryPowerReader()
    private let formatter = PowerFormatter()
    private let chargeControl = ChargeControlClient()
    private let menu = NSMenu()
    private let detailItems = (0 ..< 8).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let updatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let chargeControlStatusItem = NSMenuItem(
        title: "充电控制：正在启动",
        action: nil,
        keyEquivalent: ""
    )
    private var timer: Timer?
    private var snapshot = BatterySnapshot.unavailable()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        refresh()
        startTimer()
        startChargeControl()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        Task {
            await chargeControl.stop()
        }
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
        configureChargeControlMenu()
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

    private func configureChargeControlMenu() {
        chargeControlStatusItem.isEnabled = false
        menu.addItem(chargeControlStatusItem)

        addMenuItem(title: "设置充电范围...", action: #selector(setChargeLimits))
        addMenuItem(title: "充到上限", action: #selector(chargeToLimit))
        addMenuItem(title: "充满", action: #selector(chargeToFull))
        addMenuItem(title: "停止充电", action: #selector(stopCharging))
        menu.addItem(.separator())
        addMenuItem(title: "禁用电源适配器", action: #selector(disablePowerAdapter))
        addMenuItem(title: "启用电源适配器", action: #selector(enablePowerAdapter))
        menu.addItem(.separator())
        addMenuItem(title: "暂停后台控制", action: #selector(pauseBackgroundControl))
        addMenuItem(title: "恢复后台控制", action: #selector(resumeBackgroundControl))
        addMenuItem(title: "移除后台 daemon...", action: #selector(removeBackgroundDaemon))
    }

    @discardableResult
    private func addMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = menu.addItem(
            withTitle: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    private func startChargeControl() {
        let client = chargeControl
        Task {
            let status = await client.startDaemon()
            await MainActor.run {
                self.updateChargeControlStatus(status)
            }

            guard status == .requiresApproval else {
                return
            }

            do {
                try await client.approveDaemon(timeout: 6)
                await MainActor.run {
                    self.chargeControlStatusItem.title = "充电控制：已启用"
                }
            } catch {
                await MainActor.run {
                    self.chargeControlStatusItem.title = "充电控制：等待系统设置批准"
                    self.showError(
                        title: "需要批准后台控制",
                        error: error
                    )
                }
            }
        }
    }

    private func updateChargeControlStatus(_ status: ChargeControlClient.DaemonStatus) {
        switch status {
        case .enabled:
            chargeControlStatusItem.title = "充电控制：已启用"
        case .requiresApproval:
            chargeControlStatusItem.title = "充电控制：需要批准"
        case .notRegistered:
            chargeControlStatusItem.title = "充电控制：未注册"
        }
    }

    private func startTimer() {
        let timer = Timer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func timerFired() {
        refresh()
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func setChargeLimits() {
        let client = chargeControl
        Task {
            let currentLimits = (try? await client.currentLimits()) ?? .defaults

            guard let limits = await MainActor.run(body: {
                self.promptChargeLimits(current: currentLimits)
            }) else {
                return
            }

            self.runControlAction("设置充电范围") { client in
                try await client.setLimits(limits)
            }
        }
    }

    @objc private func chargeToLimit() {
        runControlAction("充到上限") { client in
            try await client.chargeToLimit()
        }
    }

    @objc private func chargeToFull() {
        runControlAction("充满") { client in
            try await client.chargeToFull()
        }
    }

    @objc private func stopCharging() {
        runControlAction("停止充电") { client in
            try await client.disableCharging()
        }
    }

    @objc private func disablePowerAdapter() {
        runControlAction("禁用电源适配器") { client in
            try await client.disablePowerAdapter()
        }
    }

    @objc private func enablePowerAdapter() {
        runControlAction("启用电源适配器") { client in
            try await client.enablePowerAdapter()
        }
    }

    @objc private func pauseBackgroundControl() {
        runControlAction("暂停后台控制") { client in
            try await client.pauseActivity()
        }
    }

    @objc private func resumeBackgroundControl() {
        runControlAction("恢复后台控制") { client in
            try await client.resumeActivity()
        }
    }

    @objc private func removeBackgroundDaemon() {
        guard confirm(
            title: "移除后台 daemon?",
            message: "移除后 ChargeWattMenu 将不能继续控制充电，重新打开应用时会再次注册后台 daemon。"
        ) else {
            return
        }

        runControlAction("移除后台 daemon") { client in
            try await client.removeDaemon()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refresh() {
        snapshot = reader.readSnapshot()
        statusItem.button?.title = formatter.statusTitle(for: snapshot)
        statusItem.button?.toolTip = formatter.menuLines(for: snapshot).first
        updateMenuItems()
    }

    private func updateMenuItems() {
        let lines = formatter.menuLines(for: snapshot)
        for (index, item) in detailItems.enumerated() {
            item.title = index < lines.count ? lines[index] : ""
            item.isHidden = item.title.isEmpty
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .medium
        updatedItem.title = "更新时间：\(dateFormatter.string(from: snapshot.date))"
    }

    private func runControlAction(
        _ title: String,
        operation: @escaping @Sendable (ChargeControlClient) async throws -> Void
    ) {
        let client = chargeControl
        chargeControlStatusItem.title = "充电控制：\(title)中"

        Task {
            do {
                try await operation(client)
                await MainActor.run {
                    self.chargeControlStatusItem.title = "充电控制：\(title)已发送"
                }
            } catch {
                await MainActor.run {
                    self.chargeControlStatusItem.title = "充电控制：操作失败"
                    self.showError(title: "\(title)失败", error: error)
                }
            }
        }
    }

    private func promptChargeLimits(current: ChargeLimitSettings) -> ChargeLimitSettings? {
        let minField = NSTextField(string: "\(current.minCharge)")
        let maxField = NSTextField(string: "\(current.maxCharge)")
        minField.placeholderString = "20-100"
        maxField.placeholderString = "50-100"

        let stack = NSStackView(views: [
            label("恢复充电下限 (%)"),
            minField,
            label("停止充电上限 (%)"),
            maxField
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 112)

        let alert = NSAlert()
        alert.messageText = "设置充电范围"
        alert.informativeText = "下限至少 20%，上限至少 50%，且下限不能高于上限。"
        alert.accessoryView = stack
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        guard
            let minCharge = Int(minField.stringValue),
            let maxCharge = Int(maxField.stringValue)
        else {
            showMessage(
                title: "充电范围无效",
                message: "请输入整数百分比。"
            )
            return nil
        }

        do {
            return try ChargeLimitSettings(
                minCharge: minCharge,
                maxCharge: maxCharge
            )
        } catch {
            showMessage(
                title: "充电范围无效",
                message: validationMessage(for: error)
            )
            return nil
        }
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 12)
        return field
    }

    private func validationMessage(for error: Error) -> String {
        guard let error = error as? ChargeLimitSettings.ValidationError else {
            return error.localizedDescription
        }

        switch error {
        case .minChargeBelowMinimum:
            return "恢复充电下限不能低于 20%。"
        case .maxChargeBelowMinimum:
            return "停止充电上限不能低于 50%。"
        case .maxChargeAboveMaximum:
            return "停止充电上限不能高于 100%。"
        case .minChargeAboveMaxCharge:
            return "恢复充电下限不能高于停止充电上限。"
        }
    }

    private func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(title: String, error: Error) {
        showMessage(title: title, message: error.localizedDescription)
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

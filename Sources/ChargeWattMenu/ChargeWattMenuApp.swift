import AppKit
import ChargeWattControl
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
    private enum PreferenceKey {
        static let showChargeControls = "showChargeControls"
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let snapshotReader = BatterySnapshotReaderActor()
    private let formatter = PowerFormatter()
    private let chargeControl = ChargeControlClient()
    private let menu = NSMenu()
    private let detailItems = (0 ..< 8).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let updatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleChargeControlsItem = NSMenuItem(
        title: "显示高级充电控制",
        action: #selector(toggleChargeControls),
        keyEquivalent: ""
    )
    private let chargeControlStatusItem = NSMenuItem(
        title: "充电控制：正在启动",
        action: nil,
        keyEquivalent: ""
    )
    private var coreChargeControlItems: [NSMenuItem] = []
    private var advancedChargeControlItems: [NSMenuItem] = []
    private var timer: Timer?
    private var snapshot = BatterySnapshot.unavailable()
    private var refreshTask: Task<Void, Never>?
    private var chargeControlStatusRefreshTask: Task<Void, Never>?
    private var chargeControlStatusRefreshGeneration = 0
    private var chargeControlStartTask: Task<Void, Never>?
    private var activeControlActionTask: Task<Void, Never>?
    private var statusResetTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var isShowingLimitsAlert = false
    private var chargeControlsAreSupported = true

    private var showsChargeControls: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.showChargeControls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        refresh()
        startTimer()
        if ChargeControlMenuVisibility.shouldStartDaemonOnApplicationLaunch() {
            startChargeControl()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate()
        refreshTask?.cancel()
        chargeControlStatusRefreshTask?.cancel()

        guard terminationTask == nil else {
            return .terminateLater
        }

        let client = chargeControl
        terminationTask = Task {
            await client.restoreChargingBeforeExit()
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        refreshTask?.cancel()
        chargeControlStatusRefreshTask?.cancel()
        statusResetTask?.cancel()
        activeControlActionTask?.cancel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        refreshChargeControlStatusFromDaemon()
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
        updateChargeControlsVisibility()
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
        toggleChargeControlsItem.target = self
        menu.addItem(toggleChargeControlsItem)

        chargeControlStatusItem.isEnabled = false
        setStatusTitle("充电控制：按需启用")
        addCoreChargeControlItem(chargeControlStatusItem)

        addCoreChargeControlItem(title: "设置充电范围...", action: #selector(setChargeLimits))
        addAdvancedChargeControlItem(title: "充到上限", action: #selector(chargeToLimit))
        addAdvancedChargeControlItem(title: "充满", action: #selector(chargeToFull))
        addAdvancedChargeControlItem(title: "停止充电", action: #selector(stopCharging))
        addAdvancedChargeControlItem(.separator())
        addAdvancedChargeControlItem(title: "禁用电源适配器", action: #selector(disablePowerAdapter))
        addAdvancedChargeControlItem(title: "启用电源适配器", action: #selector(enablePowerAdapter))
        addAdvancedChargeControlItem(.separator())
        addAdvancedChargeControlItem(title: "暂停后台控制", action: #selector(pauseBackgroundControl))
        addAdvancedChargeControlItem(title: "恢复后台控制", action: #selector(resumeBackgroundControl))
        addAdvancedChargeControlItem(title: "移除后台 daemon...", action: #selector(removeBackgroundDaemon))
    }

    @discardableResult
    private func addCoreChargeControlItem(title: String, action: Selector) -> NSMenuItem {
        let item = menu.addItem(
            withTitle: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        coreChargeControlItems.append(item)
        return item
    }

    private func addCoreChargeControlItem(_ item: NSMenuItem) {
        menu.addItem(item)
        coreChargeControlItems.append(item)
    }

    @discardableResult
    private func addAdvancedChargeControlItem(title: String, action: Selector) -> NSMenuItem {
        let item = menu.addItem(
            withTitle: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        advancedChargeControlItems.append(item)
        return item
    }

    private func addAdvancedChargeControlItem(_ item: NSMenuItem) {
        menu.addItem(item)
        advancedChargeControlItems.append(item)
    }

    private func updateChargeControlsVisibility() {
        toggleChargeControlsItem.state = showsChargeControls ? .on : .off
        for item in coreChargeControlItems {
            item.isHidden = ChargeControlMenuVisibility.isCoreControlHidden(
                showsAdvancedControls: showsChargeControls
            )
        }
        for item in advancedChargeControlItems {
            item.isHidden = ChargeControlMenuVisibility.isAdvancedControlHidden(
                showsAdvancedControls: showsChargeControls
            )
        }
        updateChargeControlItemEnablement()
    }

    private func setStatusTitle(_ title: String) {
        chargeControlStatusItem.title = title
        chargeControlStatusItem.isEnabled = false
    }

    private func updateChargeControlItemEnablement() {
        for item in coreChargeControlItems + advancedChargeControlItems
        where item.action != nil {
            item.isEnabled = chargeControlsAreSupported && activeControlActionTask == nil
        }
    }

    private func scheduleStatusReset() {
        statusResetTask?.cancel()
        statusResetTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self.setStatusTitle("充电控制：按需启用")
            }
        }
    }

    private func startChargeControl() {
        guard chargeControlStartTask == nil else {
            return
        }

        let client = chargeControl
        setStatusTitle("充电控制：正在启动")
        chargeControlStartTask = Task {
            defer {
                Task { @MainActor in
                    self.chargeControlStartTask = nil
                }
            }

            let status = await client.startDaemon()
            await MainActor.run {
                self.updateChargeControlStatus(status)
            }
        }
    }

    private func updateChargeControlStatus(_ status: ChargeControlClient.DaemonStatus) {
        switch status {
        case .enabled:
            chargeControlsAreSupported = true
            setStatusTitle("充电控制：已启用")
        case .requiresApproval:
            chargeControlsAreSupported = true
            setStatusTitle("充电控制：需要批准")
        case .notRegistered:
            chargeControlsAreSupported = true
            setStatusTitle("充电控制：未注册")
        }
        updateChargeControlItemEnablement()
    }

    private func updateChargeControlStatus(_ state: ChargeControlState) {
        switch state.supportStatus {
        case .enabled:
            chargeControlsAreSupported = true
            setStatusTitle("充电控制：已启用")
        case .unsupported:
            chargeControlsAreSupported = false
            setStatusTitle("充电控制：当前机型不支持")
        case .unknown:
            chargeControlsAreSupported = false
            setStatusTitle("充电控制：状态不可用")
        }
        updateChargeControlItemEnablement()
    }

    private func refreshChargeControlStatusFromDaemon() {
        let client = chargeControl
        chargeControlStatusRefreshTask?.cancel()
        chargeControlStatusRefreshGeneration += 1
        let generation = chargeControlStatusRefreshGeneration
        chargeControlStatusRefreshTask = Task {
            defer {
                Task { @MainActor in
                    if self.chargeControlStatusRefreshGeneration == generation {
                        self.chargeControlStatusRefreshTask = nil
                    }
                }
            }
            do {
                let state = try await client.currentState()
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self.chargeControlStatusRefreshGeneration == generation else {
                        return
                    }
                    self.updateChargeControlStatus(state)
                }
            } catch {
                await MainActor.run {
                    guard self.chargeControlStatusRefreshGeneration == generation else {
                        return
                    }
                    self.updateChargeControlItemEnablement()
                }
            }
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
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    @objc private func timerFired() {
        refresh()
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func toggleChargeControls() {
        let shouldShow = !showsChargeControls
        UserDefaults.standard.set(shouldShow, forKey: PreferenceKey.showChargeControls)
        updateChargeControlsVisibility()

        if shouldShow,
           ChargeControlMenuVisibility.shouldStartDaemonWhenShowingAdvancedControls(
               showsAdvancedControls: shouldShow
           ) {
            startChargeControl()
        }
    }

    @objc private func setChargeLimits() {
        guard !isShowingLimitsAlert else {
            return
        }
        guard activeControlActionTask == nil else {
            setStatusTitle("充电控制：已有操作进行中")
            scheduleStatusReset()
            return
        }

        isShowingLimitsAlert = true
        let client = chargeControl
        setStatusTitle("充电控制：读取当前范围")

        activeControlActionTask = Task {
            defer {
                Task { @MainActor in
                    self.isShowingLimitsAlert = false
                    self.activeControlActionTask = nil
                    self.updateChargeControlItemEnablement()
                }
            }

            do {
                try await client.prepareForAction(approvalTimeout: 6)
                let currentLimits = try await client.currentLimits()

                guard let limits = await MainActor.run(body: {
                    self.promptChargeLimits(current: currentLimits)
                }) else {
                    await MainActor.run {
                        self.setStatusTitle("充电控制：已取消")
                        self.scheduleStatusReset()
                    }
                    return
                }

                await MainActor.run {
                    self.setStatusTitle("充电控制：设置充电范围中")
                }
                let result = try await client.setLimitsAndApply(limits)
                await MainActor.run {
                    self.setStatusTitle("充电控制：\(self.statusText(for: result))")
                    self.scheduleStatusReset()
                }
            } catch {
                await MainActor.run {
                    self.setStatusTitle("充电控制：设置充电范围失败")
                    self.showError(title: "设置充电范围失败", error: error)
                    self.scheduleStatusReset()
                }
            }
        }
        updateChargeControlItemEnablement()
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

    private func runControlAction(
        _ title: String,
        operation: @escaping @Sendable (ChargeControlClient) async throws -> Void
    ) {
        guard activeControlActionTask == nil else {
            setStatusTitle("充电控制：已有操作进行中")
            scheduleStatusReset()
            return
        }

        let client = chargeControl
        setStatusTitle("充电控制：\(title)准备中")
        updateChargeControlItemEnablement()

        activeControlActionTask = Task {
            defer {
                Task { @MainActor in
                    self.activeControlActionTask = nil
                    self.updateChargeControlItemEnablement()
                }
            }

            do {
                try await client.prepareForAction(approvalTimeout: 6)
                await MainActor.run {
                    self.setStatusTitle("充电控制：\(title)中")
                }
                try await operation(client)
                await MainActor.run {
                    self.setStatusTitle("充电控制：\(title)已发送")
                    self.refreshChargeControlStatusFromDaemon()
                    self.scheduleStatusReset()
                }
            } catch {
                await MainActor.run {
                    self.setStatusTitle("充电控制：\(title)失败")
                    self.showError(title: "\(title)失败", error: error)
                    self.scheduleStatusReset()
                }
            }
        }
        updateChargeControlItemEnablement()
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
        alert.informativeText = "下限至少 20%，上限至少 50%，且下限必须低于上限。"
        alert.accessoryView = stack
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        do {
            return try ChargeLimitSettings.parse(
                minText: minField.stringValue,
                maxText: maxField.stringValue
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
        if error as? ChargeLimitSettings.ParseError == .notInteger {
            return "请输入整数百分比。"
        }
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
        case .minChargeNotBelowMaxCharge:
            return "恢复充电下限必须低于停止充电上限。"
        case .minChargeAboveMaxCharge:
            return "恢复充电下限不能高于停止充电上限。"
        }
    }

    private func statusText(for result: ChargeLimitApplicationResult) -> String {
        switch result {
        case .updated:
            return "范围已保存"
        case .stoppedCharging:
            return "范围已保存，已停止充电"
        case .chargingToLimit:
            return "范围已保存，正在充到上限"
        case .waitingToDropBelowLowerLimit:
            return "范围已保存，等待低于下限"
        case .stateUnavailable:
            return "范围已保存，状态不可用"
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

    private func setInformationTitle(_ item: NSMenuItem, _ title: String) {
        item.title = title
        item.isEnabled = false
    }
}

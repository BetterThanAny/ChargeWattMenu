import Foundation

public struct PowerFormatter {
    public init() {}

    public func statusTitle(for snapshot: BatterySnapshot) -> String {
        guard snapshot.batteryInstalled else {
            return "--W"
        }
        if let watts = snapshot.batteryPowerWatts {
            return compactWatts(watts)
        }
        if snapshot.externalConnected, let adapterWatts = snapshot.adapterWatts {
            return "AC\(adapterWatts)W"
        }
        return "--W"
    }

    public func menuLines(for snapshot: BatterySnapshot) -> [String] {
        var lines: [String] = []

        if let watts = snapshot.batteryPowerWatts {
            lines.append("电池侧功率：\(spacedWatts(watts))")
        } else {
            lines.append("电池侧功率：不可用")
        }

        lines.append("剩余时间：\(remainingTimeText(for: snapshot))")

        if let percent = snapshot.stateOfChargePercent {
            lines.append("电池：\(percent)%，\(stateText(for: snapshot))")
        } else {
            lines.append("电池：\(stateText(for: snapshot))")
        }

        lines.append("健康度：\(healthText(for: snapshot))")

        if let cycleCount = snapshot.cycleCount {
            lines.append("循环次数：\(cycleCount)")
        } else {
            lines.append("循环次数：不可用")
        }

        if let voltage = snapshot.batteryVoltageVolts,
           let current = snapshot.batteryCurrentAmps {
            lines.append("电池电压/电流：\(twoDecimals(voltage)) V / \(twoDecimals(current)) A")
        } else {
            lines.append("电池电压/电流：不可用")
        }

        if let adapterWatts = snapshot.adapterWatts {
            if let adapterVoltage = snapshot.adapterVoltageVolts,
               let adapterCurrent = snapshot.adapterCurrentAmps {
                lines.append(
                    "适配器档位：\(adapterWatts) W（\(oneDecimal(adapterVoltage)) V / \(twoDecimals(adapterCurrent)) A）"
                )
            } else {
                lines.append("适配器档位：\(adapterWatts) W")
            }
        } else {
            lines.append("适配器档位：不可用")
        }

        if let temperature = snapshot.temperatureCelsius {
            lines.append("温度：\(oneDecimal(temperature))°C")
        } else {
            lines.append("温度：不可用")
        }

        return lines
    }

    private func remainingTimeText(for snapshot: BatterySnapshot) -> String {
        if let minutes = snapshot.timeToFullMinutes {
            return "\(durationText(minutes))后充满"
        }
        if let minutes = snapshot.timeToEmptyMinutes {
            return "\(durationText(minutes))后耗尽"
        }
        return "不可用"
    }

    private func healthText(for snapshot: BatterySnapshot) -> String {
        guard let health = snapshot.batteryHealthPercent else {
            return "不可用"
        }
        let rawMax = snapshot.rawMaxCapacityMilliampHours.map { Int($0.rounded()) }
        let design = snapshot.designCapacityMilliampHours.map { Int($0.rounded()) }
        if let rawMax, let design {
            return "\(oneDecimal(health))%（\(rawMax) / \(design)）"
        }
        return "\(oneDecimal(health))%"
    }

    private func durationText(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes < 60 ? [.minute] : [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = []
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)分钟"
    }

    private func stateText(for snapshot: BatterySnapshot) -> String {
        if !snapshot.batteryInstalled {
            return "未安装"
        }
        if snapshot.fullyCharged {
            return "已充满"
        }
        if snapshot.isCharging {
            return "正在充电"
        }
        if snapshot.externalConnected {
            return "使用外接电源"
        }
        return "正在放电"
    }

    private func compactWatts(_ watts: Double) -> String {
        "\(oneDecimal(watts))W"
    }

    private func spacedWatts(_ watts: Double) -> String {
        "\(oneDecimal(watts)) W"
    }

    private func oneDecimal(_ value: Double) -> String {
        decimal(value, places: 1)
    }

    private func twoDecimals(_ value: Double) -> String {
        decimal(value, places: 2)
    }

    private func decimal(_ value: Double, places: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

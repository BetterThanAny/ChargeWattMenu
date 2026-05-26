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
            return "接电\(adapterWatts)W"
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

        if let percent = snapshot.stateOfChargePercent {
            lines.append("电池：\(percent)%，\(stateText(for: snapshot))")
        } else {
            lines.append("电池：\(stateText(for: snapshot))")
        }

        if let voltage = snapshot.batteryVoltageVolts,
           let current = snapshot.batteryCurrentAmps {
            lines.append("电池电压/电流：\(twoDecimals(voltage)) V / \(twoDecimals(current)) A")
        } else {
            lines.append("电池电压/电流：不可用")
        }

        if let temperature = snapshot.temperatureCelsius {
            lines.append("温度：\(oneDecimal(temperature))°C")
        } else {
            lines.append("温度：不可用")
        }

        if let cycleCount = snapshot.cycleCount {
            lines.append("循环次数：\(cycleCount)")
        } else {
            lines.append("循环次数：不可用")
        }

        return lines
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
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded(value, places: 1))
    }

    private func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded(value, places: 2))
    }

    private func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        let epsilon = value >= 0 ? 1e-9 : -1e-9
        return ((value * scale) + epsilon).rounded() / scale
    }
}

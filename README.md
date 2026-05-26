# ChargeWattMenu

ChargeWattMenu 是一个轻量 macOS 菜单栏应用，用于显示当前电池侧充电或放电功率。

它通过 IOKit 读取 `AppleSmartBattery`，并按下面公式计算：

```text
Voltage(mV) * Current(mA) / 1_000_000 = Watts
```

菜单里的适配器瓦数是充电器协商档位，不是实时进入电池的功率。

## 功能

- 菜单栏实时显示电池侧充电/放电功率
- 显示剩余充满时间或剩余耗尽时间
- 显示电池百分比和充电状态
- 显示电池健康度、当前最大容量和设计容量
- 显示循环次数、温度、电压和电流
- 显示适配器协商档位、电压和电流
- 中文菜单，零配置启动

## 开发

```zsh
swift test
swift run ChargeWattMenu
```

## 构建本地 App

```zsh
scripts/package-app.sh
open .build/release/ChargeWattMenu.app
```

## 对照 macOS 原始数据验证

```zsh
ioreg -r -c AppleSmartBattery -w0 | rg '"(Voltage|InstantAmperage|Amperage|IsCharging|ExternalConnected|AdapterDetails)"'
```

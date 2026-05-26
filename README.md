# ChargeWattMenu

ChargeWattMenu 是一个轻量 macOS 菜单栏应用，用于显示当前电池侧充电或放电功率。

它通过 IOKit 读取 `AppleSmartBattery`，并按下面公式计算：

```text
Voltage(mV) * Current(mA) / 1_000_000 = Watts
```

菜单里的适配器瓦数是充电器协商档位，不是实时进入电池的功率。

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

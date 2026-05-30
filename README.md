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
- 只读显示电池与适配器信息，不修改充电阈值或电源适配器状态
- 中文菜单，零配置启动

## 分支说明

- `main` 是公开只读版，不包含 Battery-Toolkit-SP、后台 daemon 或充电控制代码，适合直接分享给别人使用。
- `charge-control-local` 是可自签构建的充电控制版，包含 Battery-Toolkit-SP 和后台 daemon。需要控制充电范围时，请切换到该分支并用自己的 Apple Development 或 Developer ID Application 签名构建。

```zsh
git switch charge-control-local
```

不要使用别人签好的充电控制版二进制。控制版会启动后台 daemon 并修改充电行为，应只运行自己从源码构建并用自己证书签名的版本。

## 开发

```zsh
swift test
swift run ChargeWattMenu
```

## 构建本地 App

```zsh
scripts/package-app.sh
```

脚本会打印最终 `.app` 路径；默认路径在
`${TMPDIR}/ChargeWattMenu-build/<debug|release>/ChargeWattMenu.app`，也可以用
`BT_APP_OUTPUT_DIR=/path/to/output scripts/package-app.sh` 指定输出目录。没有 Apple Development
或 Developer ID Application 签名身份时，脚本会使用 ad-hoc 签名生成本机可运行版本。

`main` 的打包脚本只生成只读菜单栏 app，不会打包 daemon，也不会修改充电阈值。

## 对照 macOS 原始数据验证

```zsh
ioreg -r -c AppleSmartBattery -w0 | rg '"(Voltage|InstantAmperage|Amperage|IsCharging|ExternalConnected|AdapterDetails)"'
```

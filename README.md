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
- 设置充电恢复下限和停止充电上限
- 手动充到上限、充满、停止充电
- 启用或禁用电源适配器
- 暂停、恢复或移除后台充电控制 daemon
- 充电控制菜单可按需显示或隐藏
- 中文菜单，零配置启动

<img width="614" height="1098" alt="image" src="https://github.com/user-attachments/assets/f90b6479-c99f-4270-a2d6-75be801cfc1c" />

## 分支说明

- `main`：公开只读版，不包含 Battery-Toolkit-SP、daemon 或充电控制。
- `charge-control-local`：本地自签控制版，包含 Battery-Toolkit-SP 和后台 daemon。请自行从源码构建，不要使用别人签好的二进制控制充电。

## 开发

```zsh
swift test
swift run ChargeWattMenu
```

## 构建本地 App

充电控制版需要本机 Keychain 里有 `Apple Development` 或 `Developer ID Application`
代码签名身份。先查看可用签名：

```zsh
security find-identity -v -p codesigning
```

推荐使用自己的 bundle id 和签名身份构建：

```zsh
BT_APP_ID="com.example.ChargeWattMenu" \
BT_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
scripts/package-app.sh
```

如果用 40 位 signing hash 作为 `BT_SIGN_IDENTITY`，脚本通常会自动解析证书名。
解析失败时，显式传入证书 Common Name：

```zsh
BT_APP_ID="com.example.ChargeWattMenu" \
BT_SIGN_IDENTITY="<40-char-signing-hash>" \
BT_CODESIGN_CN="Apple Development: Your Name (TEAMID)" \
scripts/package-app.sh
```

脚本会打印最终 `.app` 路径；默认路径在
`${TMPDIR}/ChargeWattMenu-build/<debug|release>/ChargeWattMenu.app`，也可以用
`BT_APP_OUTPUT_DIR=/path/to/output scripts/package-app.sh` 指定输出目录。首次使用充电控制前，
建议把生成的 `.app` 放到 `/Applications`，启动后在 macOS “系统设置 > 通用 > 登录项与扩展”
里允许后台项目。

如果本机没有 Apple Development 或 Developer ID Application 签名身份，打包脚本会拒绝
生成可控制充电的 ad-hoc 版本。仅本机测试时可显式设置
`BT_ALLOW_ADHOC_CHARGE_CONTROL=1` 生成 debug + ad-hoc 签名版本；不要把这个版本发给别人使用。

## 安全说明

充电控制版会安装并启动后台 daemon，通过 Battery-Toolkit-SP 修改充电行为。请只运行自己从源码构建并用自己证书签名的版本。公开分享给他人时，发布源码或分支，不要发布用个人证书签好的控制版二进制。

## 验证构建

```zsh
swift test
BT_APP_OUTPUT_DIR=/tmp/ChargeWattMenu-control scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 /tmp/ChargeWattMenu-control/ChargeWattMenu.app
test -x /tmp/ChargeWattMenu-control/ChargeWattMenu.app/Contents/Library/LaunchServices/ChargeWattMenuDaemon
```

## 对照 macOS 原始数据验证

```zsh
ioreg -r -c AppleSmartBattery -w0 | rg '"(Voltage|InstantAmperage|Amperage|IsCharging|ExternalConnected|AdapterDetails)"'
```

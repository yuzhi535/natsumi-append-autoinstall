# Natsumi Append 一键修复

Firefox 更新会覆盖程序目录，删掉 Natsumi Append 依赖的 fx-autoconfig 文件，导致 `Customize Natsumi` 设置页消失。

这个脚本会重新安装 fx-autoconfig、修复 `chrome.manifest`、保留现有 Natsumi 配置，并清理 startup cache。

## 使用前

- 已经安装 **Natsumi Browser**（CSS-only 或完整版）
- 退出 Firefox
- Windows 需要以管理员身份运行 PowerShell

## macOS

```bash
curl -fsSL https://raw.githubusercontent.com/yuzhi535/natsumi-append-reapply/main/macos.sh -o /tmp/natsumi-reapply.sh
bash /tmp/natsumi-reapply.sh
```

如果提示 `Operation not permitted`，给 Terminal（或 iTerm）完全磁盘访问权限：系统设置 → 隐私与安全性 → 完全磁盘访问。

如果 Firefox 不在 `/Applications`，或 profile 不是最新的 `default-release`：

```bash
bash /tmp/natsumi-reapply.sh --profile "/path/to/profile" --firefox "/path/to/Firefox.app"
```

先看会做什么，不改文件：

```bash
bash /tmp/natsumi-reapply.sh --dry-run
```

## Windows

以管理员身份打开 PowerShell：

```powershell
irm https://raw.githubusercontent.com/yuzhi535/natsumi-append-reapply/main/windows.ps1 -OutFile $env:TEMP\natsumi-reapply.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\natsumi-reapply.ps1
```

如果 Firefox 装在非默认目录：

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\natsumi-reapply.ps1 -FirefoxDir "D:\Firefox"
```

先看会做什么：

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\natsumi-reapply.ps1 -DryRun
```

## 脚本做了什么

- 下载 [fx-autoconfig](https://github.com/greeeen-dev/fx-autoconfig)
- 备份并写入 Firefox 程序目录的 `config.js` 和 `defaults/pref/config-prefs.js`
- 备份并刷新 profile 的 `chrome/utils`、`chrome/CSS`、`chrome/resources`
- 写入指向 `natsumi/scripts` 的 `chrome.manifest`
- 确保 `userChromeJS.persistent_domcontent_callback = true`
- 删除 startup cache

备份放在 profile 下的 `natsumi-append-backups/<时间戳>/`。

## 说明

- 只支持标准安装的 Firefox。
- 脚本不修改 Natsumi 的主题和偏好设置。
- 这是非官方脚本，与 Mozilla、Natsumi Browser 项目没有隶属关系。

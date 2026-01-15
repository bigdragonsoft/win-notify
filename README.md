# WinNotify - Windows 电脑状态通知系统

监控 Windows 电脑状态（开机、登录、登录失败），通过 VPS 中转发送到 Telegram / Bark。

## 🚀 功能

- **多渠道通知**：Telegram Bot + Bark (iOS)
- **监控事件**：
  - 🟢 **系统启动**：开机时通知（附带上次关机时间）
  - 👤 **用户登录**：进入桌面时通知
  - ⚠️ **登录失败**：检测到错误密码尝试（智能过滤）
- **智能过滤**：排除系统账户和安全软件的干扰
- **安全可靠**：密钥验证、静默运行

## 📁 文件结构

```
win-notify/
├── windows/
│   ├── startup_notify.ps1   # 核心通知脚本
│   ├── config.ps1           # 配置文件
│   └── setup_tasks.ps1      # 安装脚本
└── vps/
    └── notify.php           # VPS 中转脚本
```

## � 准备工作

### 1. 获取 Telegram 配置
1. 🔍 搜索 **@BotFather**，发送 `/newbot` 创建机器人，获取 **Token**。
2. 🔍 搜索 **@userinfobot**，点击 Start 获取你的 **ID** (即 Chat ID)。
3. 🔔 别忘了先给你的机器人发送一条消息（如 `/start`）以允许它给你发信息。

### 2. 获取 Bark Key (iOS)
1. 📱 在 App Store 下载 **Bark** 应用。
2. 🚀 打开 App，你会看到一个链接，如 `https://api.day.app/YOUR_KEY_HERE/...`。
3. 🔑 **Bark Key** 就是中间那串字符 (`YOUR_KEY_HERE`)。

### 3. 生成访问密钥 (SECRET_KEY)
* 这是一个自定义密码，用于验证 Windows 发来的请求，防止接口被滥用。
* 你可以随意设置，例如：`MySecureKey2026`。

## �🛠️ 安装

### 1. VPS 端

1. 上传 `vps` 目录下的所有文件到网站目录
2. **重命名配置文件**：
   - 将 `config.sample.php` 重命名为 `config.php`
3. 编辑 `config.php`：
   - `$BOT_TOKEN` / `$CHAT_ID` - Telegram 配置
   - `$BARK_KEY` - Bark 推送 Key
   - `$SECRET_KEY` - 访问密钥
4. 测试：访问 `http://你的域名/notify.php?event=test&key=你的密钥`

### 2. Windows 端

1. **重命名配置文件**：
   - 将 `windows/config.sample.ps1` 重命名为 `config.ps1`
2. 编辑 `windows/config.ps1`：
   ```powershell
   $NOTIFY_URL = "http://你的域名/notify.php"
   $SECRET_KEY = "你的密钥"
   $MACHINE_DESCRIPTION = "我的办公室电脑" # 可选：用于区分多台机器
   ```
3. **以管理员身份**运行 `setup_tasks.ps1`

## ⚠️ 关于关机通知

由于 Windows 设计限制，**关机时无法可靠地发送网络请求**（网络服务会在脚本执行前关闭）。

**替代方案**：开机通知会附带**上次关机时间**，让你了解电脑何时关机。

## ❓ 常见问题

**Q: 冷启动没有开机通知？**
- 可能是 Windows 快速启动 (Fast Startup) 导致，可在「控制面板」->「电源选项」->「选择电源按钮的功能」中点击「更改当前不可用的设置」，然后取消勾选「启用快速启动」

**Q: 收到莫名的登录失败通知？**
- 可能是安全软件触发的，已在过滤器中排除常见的系统账户

**Q: 卸载方法？**
```powershell
Unregister-ScheduledTask -TaskName "StartupNotify_*" -Confirm:$false
Remove-Item "C:\ProgramData\StartupNotify" -Recurse -Force
```

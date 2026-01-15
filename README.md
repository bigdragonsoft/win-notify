# WinNotify - Windows 电脑监控通知系统

无需常驻后台，通过 Windows 任务计划程序监控电脑的开机、登录及登录失败事件，并通过 VPS 中转推送到 Telegram 或 Bark (iOS)。让用户随时随地了解电脑状态，及时发现异常。

## 功能特点

- **事件监控**：
  - **系统启动**：开机后发送通知，并附带上一次的关机时间。
  - **用户登录**：用于监控是否有意外登录。
  - **登录失败**：当有人尝试解锁电脑失败时报警（已过滤系统服务干扰）。
- **多端推送**：支持 Telegram Bot 和 Bark。
- **静默运行**：无窗口、无托盘图标，完全后台运行。

## 目录结构

```
win-notify/
├── windows/
│   ├── startup_notify.ps1   # 核心通知脚本
│   ├── config.ps1           # 配置文件
│   └── setup_tasks.ps1      # 安装脚本
└── vps/
    └── notify.php           # VPS 中转脚本
```

## 配置获取

为了使用通知功能，你需要提前准备以下信息：

*   **Telegram Bot**
    *   **Token**: 私聊 [@BotFather](https://t.me/BotFather) 发送 `/newbot` 创建机器人获得。
    *   **Chat ID**: 私聊 [@userinfobot](https://t.me/userinfobot) 获取你的数字 ID。
    *   *注意：创建后请先给机器人发一条消息以激活对话。*
*   **Bark (iOS)**
    *   **Key**: 在 App Store 下载 Bark，打开 App 后，在主页面的示例链接（如 `https://api.day.app/YOUR_KEY/`）中，域名后方的一串随机字符即为你的 Key。
*   **SECRET_KEY**
    *   这是为了防止接口被滥用而设置的密码，请自拟一个复杂的字符串（建议仅包含数字和字母）。

## 部署教程

### 1. 服务端部署 (VPS)

> **注意**：本项目仅提供 PHP 脚本，服务器需自备 PHP 运行环境（如 Nginx/Apache + PHP），环境搭建不属于本项目范畴。

1. 将 `vps` 目录下的文件上传至你的 Web 服务器。
2. 将 `config.sample.php` 重命名为 `config.php`，并填入以下信息：
   - **Telegram**：Bot Token 和 Chat ID。
   - **Bark**：App 内获取的 Key (URL 路径中的一段)。
   - **SECRET_KEY**：自定义密钥，用于验证客户端请求。

### 2. 客户端部署 (Windows)

1. 将 `windows/config.sample.ps1` 重命名为 `config.ps1`。
2. 编辑 `config.ps1` 填入配置：
   ```powershell
   $NOTIFY_URL = "http://你的域名/notify.php"
   $SECRET_KEY = "与服务端一致的密钥"
   $MACHINE_DESCRIPTION = "办公室电脑" # 用于区分多台设备
   ```
3. 以管理员身份运行 PowerShell，进入 `windows` 目录并执行 `.\setup_tasks.ps1` 即可完成安装。

> **提示**：安装脚本会自动将文件复制到 `C:\ProgramData\StartupNotify` 并注册任务计划。

## 常见问题

*   **关于关机通知**
    由于 Windows 关机过程中网络服务会优先被关闭，脚本很难稳定发出请求。目前的方案是在**开机通知**中附带上一次的关机时间，以间接达到监控目的。

*   **冷启动没有通知？**
    请检查是否开启了“快速启动” (Fast Startup)。控制面板 -> 电源选项 -> 选择电源按钮的功能 -> 更改当前不可用的设置 -> 取消勾选“启用快速启动”。

*   **如何卸载**
    执行以下 PowerShell 命令：
    ```powershell
    Unregister-ScheduledTask -TaskName "StartupNotify_*" -Confirm:$false
    Remove-Item "C:\ProgramData\StartupNotify" -Recurse -Force
    ```

*   **提示“在此系统上禁止运行脚本”？**
    这是 PowerShell 的安全策略限制。请以管理员身份执行以下命令开启权限：
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

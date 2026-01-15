<?php
/**
 * WinNotify - Windows 开机通知接收脚本
 * 访问方式: notify.php?event=startup&computer=PC1&ip=192.168.1.1&key=your_key
 * PHP 5.6 兼容
 */

// ============ 配置加载 ============
$configFile = __DIR__ . '/config.php';

if (file_exists($configFile)) {
    require_once $configFile;
} else {
    // 如果没有 config.php，尝试使用默认值或报错
    // 兼容旧版本的直接定义方式，但建议用户迁移到 config.php
    if (!isset($BOT_TOKEN)) $BOT_TOKEN = '';
    if (!isset($CHAT_ID)) $CHAT_ID = '';
    if (!isset($BARK_KEY)) $BARK_KEY = '';
    if (!isset($SECRET_KEY)) {
        header('HTTP/1.1 500 Internal Server Error');
        die('Error: config.php not found. Please rename config.sample.php to config.php and configure it.');
    }
}
// ==================================

// 事件类型映射
$eventTypes = array(
    'startup'      => '🟢 系统启动',
    'login'        => '👤 用户登录',
    'shutdown'     => '🔴 系统关机',
    'login_failed' => '⚠️ 登录失败警告',
    'test'         => '🔧 测试消息'
);

// 获取参数
$event = isset($_GET['event']) ? $_GET['event'] : 'unknown';
$computer = isset($_GET['computer']) ? $_GET['computer'] : '未知';
$ip = isset($_GET['ip']) ? $_GET['ip'] : '未知';
$time = isset($_GET['time']) ? $_GET['time'] : date('Y-m-d H:i:s');
$key = isset($_GET['key']) ? $_GET['key'] : '';
$lastShutdown = isset($_GET['last_shutdown']) ? $_GET['last_shutdown'] : '';

// 验证密钥
if ($SECRET_KEY !== 'your_secret_key_here' && $key !== $SECRET_KEY) {
    header('Content-Type: application/json');
    echo json_encode(array('success' => false, 'error' => 'Invalid key'));
    exit;
}

// 获取事件描述
$eventDesc = isset($eventTypes[$event]) ? $eventTypes[$event] : "❓ 未知事件({$event})";

// 构建消息 (Telegram 用 HTML)
$message_tg = "<b>{$eventDesc}</b>\n\n";
$message_tg .= "🖥️ <b>计算机:</b> {$computer}\n";
$message_tg .= "🕐 <b>时间:</b> {$time}\n";
$message_tg .= "🌐 <b>IP地址:</b> {$ip}";
// 开机通知附带上次关机时间
if ($event === 'startup' && !empty($lastShutdown)) {
    $message_tg .= "\n🔴 <b>上次关机:</b> {$lastShutdown}";
}

// 构建消息 (Bark 用纯文本)
$title_bark = str_replace(['🟢 ', '👤 ', '🔴 ', '⚠️ ', '🔧 '], '', $eventDesc); // 去掉图标作为标题
$body_bark = "计算机: {$computer}\n时间: {$time}\nIP: {$ip}";
if ($event === 'startup' && !empty($lastShutdown)) {
    $body_bark .= "\n上次关机: {$lastShutdown}";
}

// 发送 Telegram 消息
function sendTelegram($botToken, $chatId, $message) {
    if (empty($botToken) || empty($chatId)) return ['success' => true, 'skipped' => true];
    
    $url = "https://api.telegram.org/bot{$botToken}/sendMessage";
    $data = array('chat_id' => $chatId, 'text' => $message, 'parse_mode' => 'HTML');
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($data));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);
    
    return array('success' => ($httpCode == 200), 'http_code' => $httpCode, 'response' => $response, 'curl_error' => $curlError);
}

// 发送 Bark 消息
function sendBark($barkKey, $title, $body) {
    if (empty($barkKey)) return ['success' => true, 'skipped' => true];
    
    $encodedTitle = urlencode($title);
    $encodedBody = urlencode($body);
    $url = "https://api.day.app/{$barkKey}/{$encodedTitle}/{$encodedBody}?icon=https://cdn-icons-png.flaticon.com/512/2919/2919601.png&group=WindowsNotify";
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);
    
    return array('success' => ($httpCode == 200), 'http_code' => $httpCode, 'response' => $response, 'curl_error' => $curlError);
}

// 执行发送
$res_tg = sendTelegram($BOT_TOKEN, $CHAT_ID, $message_tg);
$res_bark = sendBark($BARK_KEY, $title_bark, $body_bark);

// 返回结果
header('Content-Type: application/json');

// 只要有一个成功就算成功
$tg_success = isset($res_tg['success']) ? $res_tg['success'] : false;
$bark_success = isset($res_bark['success']) ? $res_bark['success'] : false;

if ($tg_success || $bark_success) {
    echo json_encode(array('success' => true));
} else {
    // 调试模式返回详细信息
    echo json_encode(array(
        'success' => false,
        'telegram' => $res_tg,
        'bark' => $res_bark
    ));
}


?>

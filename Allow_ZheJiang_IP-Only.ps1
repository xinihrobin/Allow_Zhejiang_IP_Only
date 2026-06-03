# 1. 强制启用 TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2. 从国内稳定的静态镜像站下载【浙江省】最新 IP 列表
$Urls = @{
    "Zhejiang" = "https://fastly.jsdelivr.net/gh/metowolf/iplist@master/data/cncity/330000.txt" # 浙江
}

$AllRegionalIPs = @()

foreach ($key in $Urls.Keys) {
    Write-Host "正在获取 [$key] 的最新 IP 地址段..." -ForegroundColor Cyan
    $outputFile = "$env:TEMP\$key`_ips.txt"
    try {
        Invoke-WebRequest -Uri $Urls[$key] -OutFile $outputFile -TimeoutSec 20
        $ips = Get-Content $outputFile | Where-Object { $_ -match "^\d{1,3}\." }
        $AllRegionalIPs += $ips
        Write-Host "-> 成功载入 [$key] 共 $($ips.Count) 条网段。" -ForegroundColor Green
    } catch {
        Write-Error "下载 $key 的 IP 库失败，请检查服务器网络！"
        exit
    }
}

$TotalCount = $AllRegionalIPs.Count
Write-Host "`n总计获取到浙江省白名单网段: $TotalCount 条。" -ForegroundColor Green

# 3. 【端口修正】定义要保护的端口（3389=远程桌面, 53333=自定义 SQL 1端口3）
$TargetPorts = @("3389", "53333")

# 4. 先创建或重置【底线黑名单规则】：默认切断所有人访问这些敏感端口
$CheckBlock = Get-NetFirewallRule -DisplayName "Default_Block_SQL_RDP" -ErrorAction SilentlyContinue
if ($CheckBlock) {
    Remove-NetFirewallRule -DisplayName "Default_Block_SQL_RDP" -ErrorAction SilentlyContinue
}

New-NetFirewallRule -DisplayName "Default_Block_SQL_RDP" `
                    -Direction Inbound `
                    -Action Block `
                    -Protocol TCP `
                    -LocalPort $TargetPorts `
                    -RemoteAddress Any `
                    -Description "默认切断外网对自定义SQL和RDP的直接访问"
Write-Host "已建立底线拦截规则：默认阻止所有人。" -ForegroundColor Yellow


# 5. 清理之前可能产生的 Allow 旧规则（防止重复堆叠）
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "Allow_Zhejiang_Only_Part_*" } | Remove-NetFirewallRule

# 6. 分批将浙江白名单 IP 注入（每 500 条一组）
$ChunkSize = 500
$RuleIndex = 1

for ($i = 0; $i -lt $TotalCount; $i += $ChunkSize) {
    $Chunk = $AllRegionalIPs[$i..($i + $ChunkSize - 1)] | Where-Object { $_ -ne $null }
    $RuleName = "Allow_Zhejiang_Only_Part_$RuleIndex"
    
    Write-Host "正在写入防火墙白名单: $RuleName (导入 $($Chunk.Count) 条)..." -ForegroundColor Yellow
    
    New-NetFirewallRule -DisplayName $RuleName `
                        -Direction Inbound `
                        -Action Allow `
                        -Protocol TCP `
                        -LocalPort $TargetPorts `
                        -RemoteAddress $Chunk `
                        -Description "仅允许浙江地区访问"
    
    $RuleIndex++
}

Write-Host "`n【配置完成】浙江省专属白名单已全面成功生效！（受保护端口：3389, 53333）" -ForegroundColor Green

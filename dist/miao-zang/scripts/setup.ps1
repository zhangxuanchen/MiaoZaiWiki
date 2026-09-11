# 喵藏 · 一键准备运行环境（Windows）
#
# 做四件事：找一个 Python 3.8+ → 在 scripts\.venv 建虚拟环境 → 装抓网页依赖 → 体检。
# 依赖失败**不算失败**：记笔记 / 建书库 / 整理索引只用标准库，照样能跑。
#
# 用法（在 scripts 目录下）：
#   powershell -ExecutionPolicy Bypass -File setup.ps1
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Lock     # 用精确版本清单

param([switch]$Lock)

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $here

$req = if ($Lock) { "requirements.lock.txt" } else { "requirements.txt" }

Write-Host "喵藏 · 准备环境"
Write-Host "  目录  $here"

# ── 1. 找一个能用的 Python 3.8+ ────────────────────────────────
$pyExe = $null
$pyPre = @()          # py 启动器要带 -3
foreach ($cand in @("py", "python", "python3")) {
    if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
    $pre = @()
    if ($cand -eq "py") { $pre = @("-3") }
    $probe = $pre + @("-c", "import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)")
    & $cand @probe 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $pyExe = $cand; $pyPre = $pre; break }
}
if (-not $pyExe) {
    Write-Host "  ✗ 没找到 Python 3.8+。先装一个：https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "    （安装时记得勾上 Add Python to PATH）"
    exit 1
}
$ver = (& $pyExe @($pyPre + @("-c", "import sys;print('%d.%d.%d' % sys.version_info[:3])"))) 2>$null
Write-Host "  ✓ 解释器 $pyExe $ver"

# ── 2. 建虚拟环境 ──────────────────────────────────────────────
$venvPy = Join-Path $here ".venv\Scripts\python.exe"
if (Test-Path $venvPy) {
    Write-Host "  · 已有 .venv，跳过创建"
} else {
    & $pyExe @($pyPre + @("-m", "venv", ".venv"))
    if (-not (Test-Path $venvPy)) {
        Write-Host "  ✗ 建 venv 失败" -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ 建好 .venv"
}

# ── 3. 装依赖（装不上只是降级，不中断）──────────────────────────
& $venvPy -m pip install --quiet --upgrade pip 2>$null | Out-Null
Write-Host "  · 装依赖 $req …"
& $venvPy -m pip install --quiet -r $req
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ 依赖就绪"
} else {
    Write-Host "  ! 依赖没装全 —— 不影响用：记笔记 / 建书库 / 整理索引 / 浏览 现在就能跑"
    Write-Host "    （只有「把网页链接转成本地 md」需要那两个包）"
}

# ── 4. 体检 ────────────────────────────────────────────────────
Write-Host ""
& $venvPy fetcher.py --doctor
$code = $LASTEXITCODE

Write-Host ""
Write-Host "以后这样调："
Write-Host "  `"$venvPy`" fetcher.py --root <书库路径> --doctor"
Write-Host "  `"$venvPy`" fetcher.py --root <书库路径> <链接>"
exit $code

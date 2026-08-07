#Requires -Version 7.0
<#
.SYNOPSIS
	Локальная сборка релиза: обе платформы + (по флагу) тег и релиз на GitHub.

.DESCRIPTION
	Делает то же, что release.yml, но на своей машине — запасной путь на случай,
	когда GitHub Actions лежит или прогон не доходит до конца. Правило про версию
	то же самое: её никто не пишет руками, она берётся из имени текущей ветки
	release/vX.Y.Z. Версия расходится по файлам единственным местом —
	.github/scripts/set_version.sh, тем же, что зовёт CI.

.PARAMETER Version
	Версия без префикса v (например 0.5.0). По умолчанию выводится из имени
	текущей ветки. Указывать руками нужно только для перевыпуска не с той ветки.

.PARAMETER Publish
	После сборки закоммитить бамп версии, повесить тег vX.Y.Z, запушить и создать
	релиз на GitHub с обоими архивами. Без этого флага скрипт только собирает.

.PARAMETER Force
	Не спрашивать подтверждения перед публикацией.

.PARAMETER Godot
	Путь к godot.exe. По умолчанию ищется в «Program Files\Godot Engine» и в PATH.

.EXAMPLE
	pwsh dev/release.ps1
	Собрать обе платформы в dist/, ничего никуда не отправляя.

.EXAMPLE
	pwsh dev/release.ps1 -Publish
	Собрать и опубликовать релиз текущей версии на GitHub.
#>
[CmdletBinding()]
param(
	[string]$Version,
	[switch]$Publish,
	[switch]$Force,
	[string]$Godot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Note([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Fail([string]$Text) { throw $Text }

# --- версия движка -----------------------------------------------------------
# Берётся из action.yml, чтобы локальная сборка не разъехалась с CI по движку:
# обновили godot-version там — здесь подхватится само.
function Get-ExpectedGodotVersion {
	$actionYml = Join-Path $Root '.github/actions/godot-export/action.yml'
	$line = Select-String -Path $actionYml -Pattern '^\s*default:\s*"([0-9.]+)"' | Select-Object -First 1
	if (-not $line) { Fail "Не удалось прочитать godot-version из $actionYml" }
	return $line.Matches[0].Groups[1].Value
}

function Resolve-Godot([string]$Expected) {
	$candidates = @()
	if ($Godot) { $candidates += $Godot }
	if ($env:GODOT) { $candidates += $env:GODOT }
	# _console-сборка, а не обычная: обычная отсоединяется от консоли и не
	# печатает ни строчки, из скрипта это выглядит как молчаливый провал.
	$candidates += Get-ChildItem 'C:\Program Files\Godot Engine' -Filter 'Godot*_console.exe' -ErrorAction SilentlyContinue |
		Sort-Object Name -Descending | ForEach-Object { $_.FullName }
	$onPath = Get-Command godot -ErrorAction SilentlyContinue
	if ($onPath) { $candidates += $onPath.Source }

	foreach ($c in $candidates) {
		if ($c -and (Test-Path $c)) {
			$reported = (& $c --version 2>&1 | Select-Object -First 1)
			if ($reported -notmatch [regex]::Escape($Expected)) {
				Write-Warning "Godot по пути $c сообщает «$reported», а CI собирает на $Expected — сборка может разойтись с релизной."
			}
			return $c
		}
	}
	Fail "Не найден godot.exe. Укажи -Godot <путь> или переменную окружения GODOT."
}

# --- версия релиза -----------------------------------------------------------
function Resolve-Version {
	if ($Version) { $v = $Version }
	else {
		$branch = (& git -C $Root rev-parse --abbrev-ref HEAD).Trim()
		if ($branch -notmatch '^release/v([0-9]+\.[0-9]+\.[0-9]+)$') {
			Fail "Ветка «$branch» не называется release/vX.Y.Z — версию взять неоткуда. Переключись на версионную ветку или передай -Version X.Y.Z."
		}
		$v = $Matches[1]
	}
	if ($v -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { Fail "Версия «$v» не вида X.Y.Z" }
	return $v
}

# --- запуск движка с таймаутом ----------------------------------------------
# Импорт умеет зависать намертво (см. «Грабли» в докe про релизы): без потолка
# скрипт молча висел бы часами.
function Invoke-Godot([string]$Exe, [string[]]$Arguments, [int]$TimeoutSec = 900) {
	# Start-Process склеивает -ArgumentList через пробел и ничего не экранирует,
	# а у нас в аргументах и путь проекта («Godot Projects»), и имя пресета
	# («Windows Desktop») — без кавычек движок увидит их разрезанными пополам.
	$quoted = $Arguments | ForEach-Object { if ($_ -match '\s') { """$_""" } else { $_ } }
	$p = Start-Process -FilePath $Exe -ArgumentList $quoted -NoNewWindow -PassThru
	if (-not $p.WaitForExit($TimeoutSec * 1000)) {
		try { $p.Kill($true) } catch { }
		Fail "Godot не уложился в ${TimeoutSec}s и был убит: $Exe $($Arguments -join ' ')"
	}
	return $p.ExitCode
}

# --- упаковка ----------------------------------------------------------------
# Compress-Archive не хранит права POSIX, и распакованный на Linux бинарник
# оказывается без +x. Пишем zip руками, чтобы проставить 0755 исполняемому файлу
# — ровно то, что на раннере делает `zip` под Linux.
function New-ReleaseZip([string]$SourceDir, [string]$ZipPath, [string]$ExecutableName) {
	Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
	if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
	New-Item -ItemType Directory -Force (Split-Path -Parent $ZipPath) | Out-Null

	$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
	try {
		$base = (Resolve-Path $SourceDir).Path.TrimEnd('\')
		foreach ($file in Get-ChildItem $SourceDir -Recurse -File) {
			$rel = $file.FullName.Substring($base.Length + 1).Replace('\', '/')
			$entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
				$zip, $file.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
			# Верхние 16 бит ExternalAttributes — режим st_mode для Unix-читателей.
			# PowerShell не знает восьмеричных литералов, отсюда hex: 0755 и 0644.
			$mode = if ($file.Name -eq $ExecutableName) { 0x1ED } else { 0x1A4 }
			$entry.ExternalAttributes = $mode -shl 16
		}
	}
	finally { $zip.Dispose() }
}

# =============================================================================

$expected = Get-ExpectedGodotVersion
$godotExe = Resolve-Godot $expected
$version = Resolve-Version
$tag = "v$version"

Write-Step "Astral Genesis $tag"
Write-Note "движок:  $godotExe (ожидается $expected)"
Write-Note "корень:  $Root"

# Тег занят — значит версия уже выпускалась. Молча перезаписать сборку, которую
# кто-то уже скачал, хуже, чем упасть (то же правило, что в release.yml).
& git -C $Root rev-parse -q --verify "refs/tags/$tag" *> $null
if ($LASTEXITCODE -eq 0) {
	if ($Publish) { Fail "Тег $tag уже существует — эта версия уже выпускалась. Снеси тег и релиз руками, если правда нужен перевыпуск." }
	Write-Warning "Тег $tag уже существует — собираю, но опубликовать (-Publish) не получится."
}

Write-Step "Проставляю версию"
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bash)) { Fail "Не найден bash из Git for Windows ($bash) — им запускается set_version.sh" }
& $bash -lc "cd '$($Root -replace '\\','/')' && bash .github/scripts/set_version.sh $version"
if ($LASTEXITCODE -ne 0) { Fail "set_version.sh упал" }

Write-Step "Импорт ресурсов"
# Тот же обход зависания многопоточного импорта, что на раннере. Блок помечен и
# срезается после импорта, чтобы не осесть в project.godot и не уехать в коммит.
$projectGodot = Join-Path $Root 'project.godot'
$marker = '; --- dev/release.ps1: временно, срезается после импорта ---'
$original = Get-Content $projectGodot -Raw
try {
	Add-Content $projectGodot "`n$marker`n[editor]`n`nimport/use_multiple_threads=false`n"
	# Первый проход генерирует .uid-файлы, на которые ссылаются сцены, поэтому
	# часть зависимостей резолвится только со второго.
	Invoke-Godot $godotExe @('--headless', '--path', $Root, '--import') | Out-Null
	$code = Invoke-Godot $godotExe @('--headless', '--path', $Root, '--import')
	if ($code -ne 0) { Fail "Импорт завершился с кодом $code" }
}
finally {
	Set-Content $projectGodot -Value $original -NoNewline
}

$platforms = @(
	@{ Name = 'windows'; Preset = 'Windows Desktop'; Binary = 'AstralGenesis.exe' }
	@{ Name = 'linux';   Preset = 'Linux';           Binary = 'AstralGenesis.x86_64' }
)

$archives = @()
foreach ($p in $platforms) {
	Write-Step "Экспорт: $($p.Preset)"
	$outDir = Join-Path $Root "build/$($p.Name)"
	if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
	New-Item -ItemType Directory -Force $outDir | Out-Null

	$outFile = Join-Path $outDir $p.Binary
	$code = Invoke-Godot $godotExe @('--headless', '--path', $Root, '--export-release', $p.Preset, $outFile)
	# Godot умеет завершиться с нулевым кодом, ничего не записав (например, если
	# пресет не нашёлся) — проверяем результат явно.
	if ($code -ne 0) { Fail "Экспорт «$($p.Preset)» завершился с кодом $code" }
	if (-not (Test-Path $outFile) -or (Get-Item $outFile).Length -eq 0) {
		Fail "Экспорт «$($p.Preset)» не создал $($p.Binary)"
	}

	# Имя архива буква в букву как у CI, чтобы релизы не различались по способу сборки.
	$zip = Join-Path $Root "dist/astral-genesis-$tag-$($p.Name)-x86_64.zip"
	New-ReleaseZip $outDir $zip $p.Binary
	$archives += $zip
	Write-Note ("{0} ({1:N1} МБ)" -f (Split-Path -Leaf $zip), ((Get-Item $zip).Length / 1MB))
}

Write-Step "Готово: собраны обе платформы"
$archives | ForEach-Object { Write-Host "    $_" }

if (-not $Publish) {
	Write-Host "`nПубликация не запрашивалась. Выложить это релизом:" -ForegroundColor Yellow
	Write-Host "    pwsh dev/release.ps1 -Publish" -ForegroundColor Yellow
	return
}

# --- публикация --------------------------------------------------------------
Write-Step "Публикация релиза $tag на GitHub"

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Fail "gh не авторизован — выполни «gh auth login»" }

$branch = (& git -C $Root rev-parse --abbrev-ref HEAD).Trim()
# 0.x — игра ещё альфа, релиз идёт предварительным, чтобы «Latest release» не
# выглядел обещанием готовой игры (то же правило, что в release.yml).
$prerelease = $version -like '0.*'

if (-not $Force) {
	Write-Host ""
	Write-Host "  тег:      $tag (на HEAD ветки $branch)" -ForegroundColor White
	Write-Host "  релиз:    Astral Genesis $tag$(if ($prerelease) { ' (предварительный)' })" -ForegroundColor White
	Write-Host "  архивы:   $($archives.Count) шт." -ForegroundColor White
	Write-Host "  push:     origin $branch и origin $tag" -ForegroundColor White
	$answer = Read-Host "`nПубликуем? Это видно всем (y/N)"
	if ($answer -notin @('y', 'Y', 'д', 'Д')) { Write-Host "Отменено."; return }
}

$dirty = & git -C $Root status --porcelain -- project.godot export_presets.cfg
if ($dirty) {
	Write-Note "коммичу бамп версии"
	& git -C $Root add project.godot export_presets.cfg
	& git -C $Root commit -m "chore: версия $version"
	if ($LASTEXITCODE -ne 0) { Fail "Не удалось закоммитить бамп версии" }
}

# Тег вешается на коммит бампа, а не на что попало: иначе в теге лежал бы
# исходник со старым номером версии.
& git -C $Root tag -a $tag -m "Astral Genesis $tag"
if ($LASTEXITCODE -ne 0) { Fail "Не удалось создать тег $tag" }

& git -C $Root push origin $branch
if ($LASTEXITCODE -ne 0) { Fail "Не удалось запушить ветку $branch" }
& git -C $Root push origin $tag
if ($LASTEXITCODE -ne 0) { Fail "Не удалось запушить тег $tag" }

$ghArgs = @('release', 'create', $tag) + $archives + @('--title', "Astral Genesis $tag", '--generate-notes')
if ($prerelease) { $ghArgs += '--prerelease' }
& gh $ghArgs
if ($LASTEXITCODE -ne 0) { Fail "gh release create упал" }

Write-Step "Релиз $tag опубликован"

#Requires -Version 7.0
<#
.SYNOPSIS
	Локальная сборка проекта под Windows и Linux; по флагу — ещё и релиз на GitHub.

.DESCRIPTION
	Основной режим — просто выдать готовые архивы в dist/: погонять самому,
	раздать на тест. Ветка при этом любая, ничего никуда не отправляется, версия
	берётся из project.godot как есть.

	Если ветка называется release/vX.Y.Z, скрипт дополнительно проставляет версию
	через .github/scripts/set_version.sh — тот же и единственный способ, которым
	это делает CI, — и тогда же становится доступен -Publish: тег и релиз на
	GitHub. Это запасной путь на случай, когда Actions недоступен; обычный путь
	релиза — мёрж PR из версионной ветки в master, дальше всё делает release.yml.

.PARAMETER Config
	release (по умолчанию) или debug. Debug-сборка идёт на отладочных шаблонах:
	работает удалённый отладчик, видны стеки и вывод print. Архив получает суффикс
	-debug, чтобы не перепутать с раздаточным.

.PARAMETER Platform
	windows, linux или both (по умолчанию). Одна платформа — вдвое короче цикл,
	когда собираешь просто посмотреть.

.PARAMETER Version
	Версия без префикса v (например 0.5.0). По умолчанию выводится из имени ветки
	release/vX.Y.Z, а вне такой ветки не трогается вовсе.

.PARAMETER Publish
	После сборки закоммитить бамп версии, повесить тег vX.Y.Z, запушить и создать
	релиз на GitHub с обоими архивами. Требует версионной ветки и -Config release.

.PARAMETER Force
	Не спрашивать подтверждения перед публикацией.

.PARAMETER Godot
	Путь к godot.exe. По умолчанию ищется в «Program Files\Godot Engine» и в PATH.

.EXAMPLE
	pwsh dev/release.ps1
	Обе платформы, release, в dist/. Ничего никуда не отправляется.

.EXAMPLE
	pwsh dev/release.ps1 -Config debug -Platform windows
	Быстрая отладочная сборка под Windows — погонять самому.

.EXAMPLE
	pwsh dev/release.ps1 -Publish
	Собрать и опубликовать релиз текущей версии на GitHub.
#>
[CmdletBinding()]
param(
	# -Debug занять нельзя: это общий параметр самого PowerShell, отсюда -Config.
	[ValidateSet('release', 'debug')]
	[string]$Config = 'release',
	[ValidateSet('both', 'windows', 'linux')]
	[string]$Platform = 'both',
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

# --- версия и метка ----------------------------------------------------------
# Версия проставляется в файлы только тогда, когда её есть откуда взять — с
# версионной ветки. На любой другой ветке сборка всё равно должна получаться:
# это обычный «собрать и посмотреть», а не выпуск. Тогда версия остаётся той,
# что лежит в project.godot, а архив метится именем ветки — как это делает CI
# для сборок по PR.
function Resolve-Release {
	$branch = (& git -C $Root rev-parse --abbrev-ref HEAD).Trim()

	$v = $null
	if ($Version) { $v = $Version }
	elseif ($branch -match '^release/v([0-9]+\.[0-9]+\.[0-9]+)$') { $v = $Matches[1] }

	if ($v -and $v -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { Fail "Версия «$v» не вида X.Y.Z" }

	if ($v) { $label = "v$v" }
	else {
		# Метка уходит в имя файла, а имя ветки может содержать слеш и прочее.
		$label = ($branch -replace '[^A-Za-z0-9._-]', '-')
	}

	return [pscustomobject]@{ Branch = $branch; Version = $v; Label = $label }
}

function Get-ProjectVersion {
	$line = Select-String -Path (Join-Path $Root 'project.godot') -Pattern '^config/version="([^"]*)"' | Select-Object -First 1
	if ($line) { return $line.Matches[0].Groups[1].Value }
	return '<не задана>'
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
$rel = Resolve-Release
$tag = if ($rel.Version) { "v$($rel.Version)" } else { $null }

# Debug-архив помечен в имени: перепутать его с раздаточным легко, а весит и
# ведёт себя он иначе (отладочные шаблоны, работающий удалённый отладчик).
$suffix = if ($Config -eq 'debug') { '-debug' } else { '' }

Write-Step "Astral Genesis — сборка $Config"
Write-Note "ветка:    $($rel.Branch)"
Write-Note "версия:   $(if ($rel.Version) { "$($rel.Version) (проставлю в файлы)" } else { "$(Get-ProjectVersion) — из project.godot, ветка не версионная" })"
Write-Note "метка:    $($rel.Label)"
Write-Note "платформы: $Platform"
Write-Note "движок:   $godotExe (ожидается $expected)"

if ($Publish) {
	if (-not $tag) { Fail "Публиковать нечего: ветка «$($rel.Branch)» не называется release/vX.Y.Z. Переключись на версионную ветку или передай -Version X.Y.Z." }
	if ($Config -ne 'release') { Fail "-Publish только для -Config release: отладочная сборка в релиз не выкладывается." }

	# Тег занят — значит версия уже выпускалась. Молча перезаписать сборку,
	# которую кто-то уже скачал, хуже, чем упасть (правило из release.yml).
	& git -C $Root rev-parse -q --verify "refs/tags/$tag" *> $null
	if ($LASTEXITCODE -eq 0) { Fail "Тег $tag уже существует — эта версия уже выпускалась. Снеси тег и релиз руками, если правда нужен перевыпуск." }
}

if ($rel.Version) {
	Write-Step "Проставляю версию $($rel.Version)"
	$bash = 'C:\Program Files\Git\bin\bash.exe'
	if (-not (Test-Path $bash)) { Fail "Не найден bash из Git for Windows ($bash) — им запускается set_version.sh" }
	& $bash -lc "cd '$($Root -replace '\\','/')' && bash .github/scripts/set_version.sh $($rel.Version)"
	if ($LASTEXITCODE -ne 0) { Fail "set_version.sh упал" }
}

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
) | Where-Object { $Platform -eq 'both' -or $_.Name -eq $Platform }

# Ключ CLI ровно один на конфигурацию: он же выбирает набор шаблонов экспорта.
$exportFlag = if ($Config -eq 'debug') { '--export-debug' } else { '--export-release' }

$archives = @()
foreach ($p in $platforms) {
	Write-Step "Экспорт: $($p.Preset) ($Config)"
	$outDir = Join-Path $Root "build/$($p.Name)-$Config"
	if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
	New-Item -ItemType Directory -Force $outDir | Out-Null

	$outFile = Join-Path $outDir $p.Binary
	$code = Invoke-Godot $godotExe @('--headless', '--path', $Root, $exportFlag, $p.Preset, $outFile)
	# Godot умеет завершиться с нулевым кодом, ничего не записав (например, если
	# пресет не нашёлся) — проверяем результат явно.
	if ($code -ne 0) { Fail "Экспорт «$($p.Preset)» завершился с кодом $code" }
	if (-not (Test-Path $outFile) -or (Get-Item $outFile).Length -eq 0) {
		Fail "Экспорт «$($p.Preset)» не создал $($p.Binary)"
	}

	# Имя архива буква в букву как у CI, чтобы релизы не различались по способу сборки.
	$zip = Join-Path $Root "dist/astral-genesis-$($rel.Label)-$($p.Name)-x86_64$suffix.zip"
	New-ReleaseZip $outDir $zip $p.Binary
	$archives += $zip
	Write-Note ("{0} ({1:N1} МБ)" -f (Split-Path -Leaf $zip), ((Get-Item $zip).Length / 1MB))
}

Write-Step "Готово"
$archives | ForEach-Object { Write-Host "    $_" }

if (-not $Publish) {
	if ($Config -eq 'debug') {
		Write-Host "`nЭто отладочная сборка: работает удалённый отладчик и вывод print, для раздачи не годится." -ForegroundColor Yellow
	}
	elseif ($tag) {
		Write-Host "`nВыложить это релизом на GitHub:" -ForegroundColor Yellow
		Write-Host "    pwsh dev/release.ps1 -Publish" -ForegroundColor Yellow
		Write-Host "Обычный путь релиза — мёрж PR в master, дальше release.yml сделает то же сам." -ForegroundColor DarkGray
	}
	return
}

# --- публикация --------------------------------------------------------------
Write-Step "Публикация релиза $tag на GitHub"

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Fail "gh не авторизован — выполни «gh auth login»" }

# 0.x — игра ещё альфа, релиз идёт предварительным, чтобы «Latest release» не
# выглядел обещанием готовой игры (то же правило, что в release.yml).
$prerelease = $rel.Version -like '0.*'

if (-not $Force) {
	Write-Host ""
	Write-Host "  тег:      $tag (на HEAD ветки $($rel.Branch))" -ForegroundColor White
	Write-Host "  релиз:    Astral Genesis $tag$(if ($prerelease) { ' (предварительный)' })" -ForegroundColor White
	Write-Host "  архивы:   $($archives.Count) шт." -ForegroundColor White
	Write-Host "  push:     origin $($rel.Branch) и origin $tag" -ForegroundColor White
	$answer = Read-Host "`nПубликуем? Это видно всем (y/N)"
	if ($answer -notin @('y', 'Y', 'д', 'Д')) { Write-Host "Отменено."; return }
}

$dirty = & git -C $Root status --porcelain -- project.godot export_presets.cfg
if ($dirty) {
	Write-Note "коммичу бамп версии"
	& git -C $Root add project.godot export_presets.cfg
	& git -C $Root commit -m "chore: версия $($rel.Version)"
	if ($LASTEXITCODE -ne 0) { Fail "Не удалось закоммитить бамп версии" }
}

# Тег вешается на коммит бампа, а не на что попало: иначе в теге лежал бы
# исходник со старым номером версии.
& git -C $Root tag -a $tag -m "Astral Genesis $tag"
if ($LASTEXITCODE -ne 0) { Fail "Не удалось создать тег $tag" }

# $($...) обязательно: в позиции аргумента PowerShell не разбирает `$rel.Branch`
# как обращение к свойству и передал бы «@{...}.Branch» строкой.
& git -C $Root push origin $($rel.Branch)
if ($LASTEXITCODE -ne 0) { Fail "Не удалось запушить ветку $($rel.Branch)" }
& git -C $Root push origin $tag
if ($LASTEXITCODE -ne 0) { Fail "Не удалось запушить тег $tag" }

$ghArgs = @('release', 'create', $tag) + $archives + @('--title', "Astral Genesis $tag", '--generate-notes')
if ($prerelease) { $ghArgs += '--prerelease' }
& gh $ghArgs
if ($LASTEXITCODE -ne 0) { Fail "gh release create упал" }

Write-Step "Релиз $tag опубликован"

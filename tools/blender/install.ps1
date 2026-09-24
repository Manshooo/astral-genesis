#Requires -Version 7.0
<#
.SYNOPSIS
	Связывает копию плагина в репозитории с папкой расширений Blender.

.DESCRIPTION
	Плагин живёт в двух местах, и это главный риск такой раскладки: Blender
	грузит его из своей папки расширений, а история и ревью — из репозитория.
	Разойдясь, эти копии молча превращаются в две разные программы.

	По умолчанию скрипт делает не копию, а СВЯЗЬ (junction): папка расширений
	становится тем же каталогом, что и в репозитории, и вопрос «в какой копии я
	только что правил» перестаёт существовать. Junction на каталог не требует
	прав администратора, в отличие от символической ссылки.

	Копия остаётся вариантом для случая, когда связывать нежелательно —
	например, чтобы поставить плагин на машину, где репозитория нет.

.PARAMETER Mode
	Junction (по умолчанию) или Copy.

.PARAMETER Pull
	Обратное направление: забрать в репозиторий то, что лежит в папке
	расширений. Нужно ровно один раз — если правки делались в установленной
	копии, а связи ещё нет.

.PARAMETER BlenderVersion
	Версия Blender, например 5.2. По умолчанию берётся самая новая из
	установленных.

.EXAMPLE
	pwsh tools/blender/install.ps1

.EXAMPLE
	pwsh tools/blender/install.ps1 -Pull
#>

[CmdletBinding()]
param(
	[ValidateSet("Junction", "Copy")]
	[string]$Mode = "Junction",
	[switch]$Pull,
	[string]$BlenderVersion = ""
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Note([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Fail([string]$Text) { throw $Text }

$source = Join-Path $PSScriptRoot 'godot_pipeline'
if (-not (Test-Path $source)) { Fail "Не нашёл плагин: $source" }

$root = Join-Path $env:APPDATA 'Blender Foundation\Blender'
if (-not (Test-Path $root)) { Fail "Blender не установлен для этого пользователя: $root" }

if (-not $BlenderVersion) {
	$versions = Get-ChildItem $root -Directory |
		Where-Object { $_.Name -match '^\d+\.\d+$' } |
		Sort-Object { [version]$_.Name } -Descending
	if (-not $versions) { Fail "В «$root» нет ни одной версии Blender" }
	$BlenderVersion = $versions[0].Name
}

$target = Join-Path $root "$BlenderVersion\extensions\user_default\godot_pipeline"

Write-Step "godot_pipeline -> Blender $BlenderVersion"
Write-Note "репозиторий: $source"
Write-Note "расширения:  $target"

if ($Pull) {
	if (-not (Test-Path $target)) { Fail "В папке расширений плагина нет: $target" }
	$item = Get-Item $target -Force
	if ($item.LinkType) { Fail "Это уже связь ($($item.LinkType)) — забирать нечего." }
	[IO.Directory]::Delete($source, $true)
	Copy-Item $target $source -Recurse -Force
	$cache = Join-Path $source '__pycache__'
	if (Test-Path $cache) { [IO.Directory]::Delete($cache, $true) }
	Write-Host "    Забрано в репозиторий. Дальше — git diff." -ForegroundColor Green
	return
}

if (Test-Path $target) {
	$item = Get-Item $target -Force
	if ($item.LinkType) {
		Write-Note "снимаю прежнюю связь ($($item.LinkType))"
		[IO.Directory]::Delete($target)
	} else {
		# Не удаляем молча: в этой папке может лежать единственная копия правок,
		# сделанных прямо в установленном расширении.
		$backup = "$target.backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
		Move-Item $target $backup
		Write-Note "прежняя папка отложена в $backup"
	}
}

[IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null

if ($Mode -eq 'Junction') {
	try {
		New-Item -ItemType Junction -Path $target -Target $source | Out-Null
		Write-Host "    Связано. Правки в репозитории видны Blender сразу." -ForegroundColor Green
		Write-Note "Blender положит сюда __pycache__ — он в .gitignore."
		return
	} catch {
		Write-Warning "Junction не получился ($($_.Exception.Message)), кладу копией."
	}
}

Copy-Item $source $target -Recurse -Force
$cache = Join-Path $target '__pycache__'
if (Test-Path $cache) { [IO.Directory]::Delete($cache, $true) }
Write-Host "    Скопировано." -ForegroundColor Green
Write-Note "Это КОПИЯ: правки в репозитории сюда сами не попадут, прогоняй заново."

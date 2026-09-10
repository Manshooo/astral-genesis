#Requires -Version 7.0
<#
.SYNOPSIS
	Прогоняет проверки плагина godot_pipeline и печатает единый вердикт.

.DESCRIPTION
	Две половины, потому что и пайплайн состоит из двух половин:

	  * Blender — имена карт Ucupaint, разбор [layer_names], запись метаданных
	    коллизий, валидатор, ренейминг файлов на диске. В конце экспортирует
	    фикстуру с рэгдоллом.
	  * Godot — импортирует эту фикстуру и смотрит, что из метаданных собрались
	    настоящие узлы: Skeleton3D, PhysicalBoneSimulator3D, PhysicalBone3D с
	    формой. Метаданные без скрипта постимпорта не делают ничего, так что
	    проверять надо именно результат импорта, а не extras.

	Тестируется КОПИЯ ИЗ РЕПОЗИТОРИЯ, а не установленное расширение: плагин
	копируется во временную папку скриптов, и Blender запускается с
	--factory-startup. Иначе прогон молча проверял бы другой код.

	Всё пишется во временную папку, репозиторий не затрагивается.

.PARAMETER BlenderPath
	Путь к blender.exe. По умолчанию — известный путь на машине разработчика.

.PARAMETER GodotPath
	Путь к Godot. По умолчанию ищется в "Program Files\Godot Engine".
	Нужна консольная сборка: обычная detach'ится и ничего не печатает.

.PARAMETER Work
	Временная папка. Держится КОРОТКОЙ намеренно: под длинным путём создание
	вложенных папок ассетов на Windows падает с WinError 206.

.PARAMETER Only
	blender или godot — прогнать только одну половину. Godot-половине нужна
	фикстура, так что в одиночку она работает только после полного прогона
	с -KeepWork.

.PARAMETER KeepWork
	Не удалять временную папку — чтобы посмотреть, что там получилось.

.EXAMPLE
	pwsh tools/blender/tests/run_addon_tests.ps1

.EXAMPLE
	pwsh tools/blender/tests/run_addon_tests.ps1 -Only blender -KeepWork
#>

[CmdletBinding()]
param(
	[string]$BlenderPath = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
	[string]$GodotPath = "",
	[string]$Work = "C:\Users\$env:USERNAME\AppData\Local\Temp\gp_addon_tests",
	[ValidateSet("all", "blender", "godot")]
	[string]$Only = "all",
	[switch]$KeepWork
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Note([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Fail([string]$Text) { throw $Text }

function Resolve-Godot([string]$Preferred) {
	if ($Preferred) {
		if (-not (Test-Path $Preferred)) { Fail "Не найден Godot: $Preferred" }
		return $Preferred
	}
	$base = "C:\Program Files\Godot Engine"
	if (-not (Test-Path $base)) { Fail "Не найдена папка «$base». Передай -GodotPath." }
	# Консольная сборка обязательна: обычная отсоединяется от консоли, и вывод
	# проверок просто некуда прочитать.
	$found = Get-ChildItem $base -Recurse -Filter "*_console.exe" -ErrorAction SilentlyContinue |
		Sort-Object FullName -Descending | Select-Object -First 1
	if (-not $found) { Fail "В «$base» нет консольной сборки Godot. Передай -GodotPath." }
	return $found.FullName
}

function Remove-Tree([string]$Path) {
	if (Test-Path $Path) { [IO.Directory]::Delete($Path, $true) }
}

# --- подготовка ------------------------------------------------------------

$tests = $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $tests))
if (-not (Test-Path (Join-Path $repo 'project.godot'))) {
	Fail "Не нашёл корень проекта: ожидал project.godot в $repo"
}
$addon = Join-Path $repo 'tools\blender\godot_pipeline'
if (-not (Test-Path $addon)) { Fail "Не нашёл плагин: $addon" }
if (-not (Test-Path $BlenderPath)) { Fail "Не найден Blender: $BlenderPath" }
$godot = Resolve-Godot $GodotPath

$project = Join-Path $Work 'project'
$scripts = Join-Path $Work 'scripts'

Write-Step "Проверки плагина godot_pipeline"
Write-Note "плагин:  $addon"
Write-Note "blender: $BlenderPath"
Write-Note "godot:   $godot"
Write-Note "работа:  $Work"

if ($Only -ne 'godot') {
	Remove-Tree $Work
	[IO.Directory]::CreateDirectory((Join-Path $scripts 'addons')) | Out-Null
	[IO.Directory]::CreateDirectory($project) | Out-Null

	Copy-Item $addon (Join-Path $scripts 'addons\godot_pipeline') -Recurse -Force
	Remove-Tree (Join-Path $scripts 'addons\godot_pipeline\__pycache__')

	# Слои с дыркой в нумерации намеренно: так проверяется и разбор, и подпись
	# «Layer N» для безымянного слоя.
	$projectFile = @'
config_version=5

[application]

config/name="godot_pipeline tests"
config/features=PackedStringArray("4.7", "Forward Plus")

[layer_names]

3d_physics/layer_1="static_colliders"
3d_physics/layer_2="player"
3d_physics/layer_3="enemies"
3d_physics/layer_7="permeable"
'@
	[IO.File]::WriteAllText((Join-Path $project 'project.godot'), $projectFile)
}

Copy-Item (Join-Path $tests 'verify_ragdoll.gd') $project -Force -ErrorAction SilentlyContinue

$failed = $false

# --- Blender ---------------------------------------------------------------

if ($Only -ne 'godot') {
	Write-Step "Blender"
	$env:BLENDER_USER_SCRIPTS = $scripts
	$env:GP_TEST_PROJECT = $project
	$env:GP_REAL_PROJECT = $repo
	$log = Join-Path $Work 'blender.log'
	& $BlenderPath --background --factory-startup --python (Join-Path $tests 'test_addon.py') *> $log
	$code = $LASTEXITCODE
	$out = Get-Content $log
	$out | Where-Object { $_ -match '^(PASS|FAIL|===|---)' } | ForEach-Object { "  $_" }
	# Blender выходит с кодом 0, если скрипт вообще не запустился — синтаксическая
	# ошибка в тесте или несобравшийся импорт. Без этой проверки прогон объявлял
	# бы «зелено», не выполнив ни одной проверки.
	if (-not ($out -match '^=== ИТОГ')) {
		$failed = $true
		Write-Host "  Blender не дошёл до итога — тест не отработал." -ForegroundColor Red
		$out | Select-Object -Last 12 | ForEach-Object { "    $_" }
	}
	if ($code -ne 0) {
		$failed = $true
		Write-Host "  подробности: $log" -ForegroundColor DarkGray
	}
}

# --- Godot -----------------------------------------------------------------

if ($Only -ne 'blender') {
	Write-Step "Godot"
	if (-not (Test-Path (Join-Path $project 'assets'))) {
		Fail "Нет фикстуры в $project. Blender-половина не отработала."
	}
	$importLog = Join-Path $Work 'godot_import.log'
	& $godot --headless --path $project --import *> $importLog
	Select-String -Path $importLog -Pattern 'godot_pipeline' | ForEach-Object { "  " + $_.Line }

	$verifyLog = Join-Path $Work 'godot_verify.log'
	& $godot --headless --path $project --script res://verify_ragdoll.gd --quit-after 300 *> $verifyLog
	$code = $LASTEXITCODE
	Get-Content $verifyLog | Where-Object { $_ -match '^(PASS|FAIL|===|  - )' } | ForEach-Object { "  $_" }
	if ($code -ne 0) {
		$failed = $true
		Write-Host "  подробности: $verifyLog" -ForegroundColor DarkGray
	}
}

# --- итог ------------------------------------------------------------------

Write-Step "Итог"
if ($failed) {
	Write-Host "    ЕСТЬ ПРОВАЛЫ" -ForegroundColor Red
} else {
	Write-Host "    ВСЁ ЗЕЛЁНОЕ" -ForegroundColor Green
}

if ($KeepWork) {
	Write-Note "временная папка оставлена: $Work"
} elseif (-not $failed) {
	Remove-Tree $Work
} else {
	Write-Note "временная папка оставлена для разбора: $Work"
}

exit ([int]$failed)

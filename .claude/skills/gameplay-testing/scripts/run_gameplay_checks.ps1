<#
.SYNOPSIS
    Прогоняет headless sanity-check'и Astral Genesis и печатает единый вердикт.

.DESCRIPTION
    Оборачивает dev-сценарии в консистентный CI-подобный запуск:
      - dev/*_check.tscn — любой сценарий, названный по этому шаблону
        (body_traits_check, stat_modifiers_check, body_form_check, …),
        подхватывается АВТОМАТИЧЕСКИ: он сам печатает ok/FAIL по каждому
        ассерту и выходит нужным кодом (см. SKILL.md, §«Как писать проверку»).
        Ничего регистрировать вручную не нужно — новый файл с этим суффиксом
        подхватится сам при следующем прогоне.
      - dev/gen_verifier.tscn — единственный сценарий вне этого шаблона:
        генератор графа + библиотека пресетов на SEED_COUNT сидах; ничего не
        возвращает и не квитится сам, поэтому вывод парсится на
        "недобор дверей" / "недостижимо" / "проблем". Остаётся отдельным
        случаем, а не подгоняется под общий шаблон.

    Ни то, ни другое не подменяет ручной плейтест — см. SKILL.md, раздел
    «Чек-лист ручного плейтеста».

.PARAMETER GodotPath
    Путь к Godot-исполняемому файлу. По умолчанию — известный путь на машине
    разработчика (console-сборка: обычная detach'ится и не печатает в консоль).

.PARAMETER Check
    Какую проверку прогнать: "All" (по умолчанию, всё), "Gen" (только
    gen_verifier), либо имя файла любого dev/*_check.tscn без расширения
    (например "body_traits_check"). "Body" остаётся алиасом
    "body_traits_check" для обратной совместимости.

.PARAMETER ListChecks
    Только напечатать, какие dev/*_check.tscn найдены, и выйти — без запуска
    Godot. Полезно после того как в dev/ добавился новый сценарий.

.PARAMETER SkipSubmoduleCheck
    Не проверять/не инициализировать addons/gecs. Использовать, если уже
    заведомо инициализирован — проверка дешёвая, но пропустить можно.

.EXAMPLE
    ./run_gameplay_checks.ps1
    Прогоняет gen_verifier и все найденные dev/*_check.tscn известным Godot.

.EXAMPLE
    ./run_gameplay_checks.ps1 -Check body_traits_check -GodotPath "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"

.EXAMPLE
    ./run_gameplay_checks.ps1 -ListChecks
    Показывает, что сейчас будет прогнано под "-Check All", без запуска.
#>
param(
    [string]$GodotPath = "C:\Program Files\Godot Engine\4.7.2\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Check = "All",
    [switch]$ListChecks,
    [switch]$SkipSubmoduleCheck
)

$ErrorActionPreference = "Stop"

function Find-RepoRoot {
    $dir = Split-Path -Parent $PSScriptRoot
    while ($true) {
        $dir = Split-Path -Parent $dir
        if (Test-Path (Join-Path $dir "project.godot")) { return $dir }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir -or [string]::IsNullOrEmpty($parent)) {
            throw "Не найден project.godot выше $PSScriptRoot — запускать внутри репозитория."
        }
    }
}

$RepoRoot = Find-RepoRoot

# Все dev/*_check.tscn — это и есть регистр: имя файла по шаблону из
# SKILL.md уже значит «самостоятельный ассерт-сценарий», отдельного списка не
# нужно. Обнаруживаем каждый раз заново, а не храним статически, — иначе
# ровно этот файл снова разойдётся с dev/ при следующем новом сценарии.
function Get-GenericChecks {
    Get-ChildItem (Join-Path $RepoRoot "dev") -Filter "*_check.tscn" -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { $_.BaseName }
}

if ($ListChecks) {
    Write-Host "gen_verifier (особый случай, не по шаблону *_check.tscn)"
    Get-GenericChecks | ForEach-Object { Write-Host $_ }
    exit 0
}

Write-Host "Репозиторий: $RepoRoot"

if (-not (Test-Path $GodotPath)) {
    # Известный путь не подошёл — поищем любую console-сборку Godot 4.
    $fallback = Get-ChildItem "C:\Program Files\Godot Engine\" -Filter "*_console.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($fallback) {
        Write-Host "Godot по умолчанию не найден, использую: $fallback"
        $GodotPath = $fallback
    } else {
        throw "Godot не найден ни по '$GodotPath', ни в 'C:\Program Files\Godot Engine\'. Передайте -GodotPath явно."
    }
}

if (-not $SkipSubmoduleCheck) {
    Push-Location $RepoRoot
    try {
        $status = git submodule status addons/gecs 2>$null
        if ($status -match "^-") {
            Write-Host "addons/gecs не инициализирован — запускаю 'git submodule update --init addons/gecs'."
            git submodule update --init addons/gecs
        }
    } finally {
        Pop-Location
    }
}

$overallFail = $false

function Run-GenericCheck([string]$Name) {
    Write-Host "`n=== $Name ==="
    & $GodotPath --headless --path $RepoRoot "res://dev/$Name.tscn" --quit-after 900
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Host "FAIL: $Name вышел с кодом $code (см. вывод выше — строки 'FAIL')" -ForegroundColor Red
        return $false
    }
    Write-Host "OK: $Name — все ассерты прошли." -ForegroundColor Green
    return $true
}

function Run-GenVerifier {
    Write-Host "`n=== gen_verifier ==="
    $output = & $GodotPath --headless --path $RepoRoot "res://dev/gen_verifier.tscn" --quit-after 300 2>&1
    $output | ForEach-Object { Write-Host $_ }

    $fail = $false

    $summaryLine = $output | Select-String -Pattern "Итог: макс\. недостижимо по графу=(\d+), по дверям=(\d+)"
    if (-not $summaryLine) {
        Write-Host "FAIL: не нашёл итоговую строку 'Итог: ...' в выводе — сцена не отработала до конца?" -ForegroundColor Red
        return $false
    }
    $m = $summaryLine.Matches[0]
    $unreachableGraph = [int]$m.Groups[1].Value
    $unreachableDoors = [int]$m.Groups[2].Value
    if ($unreachableGraph -gt 0) {
        Write-Host "FAIL: недостижимо по графу > 0 ($unreachableGraph) — граф генератора несвязен, это баг генератора, не дверей." -ForegroundColor Red
        $fail = $true
    }
    if ($unreachableDoors -gt 0) {
        Write-Host "ВНИМАНИЕ: недостижимо по дверям = $unreachableDoors — не обязательно фейл (см. SKILL.md), но проверьте, не выросло ли число." -ForegroundColor Yellow
    }

    if ($output | Select-String -Pattern "проблем:") {
        Write-Host "FAIL: RS_RoomPresetLibrary.validate() нашёл проблемы (см. строки 'validate(): N проблем' выше)." -ForegroundColor Red
        $fail = $true
    }
    if ($output | Select-String -Pattern "room_preset_library не назначена") {
        Write-Host "FAIL: library == null — data/game_config.tres не ссылается на room_preset_library." -ForegroundColor Red
        $fail = $true
    }

    if (-not $fail) {
        Write-Host "OK: gen_verifier — граф связен, пресеты валидны." -ForegroundColor Green
    }
    return -not $fail
}

$genericChecks = Get-GenericChecks

# "Body" — алиас "body_traits_check" для обратной совместимости с тем, как
# параметр назывался до автообнаружения (см. SKILL.md, старые примеры).
$resolvedCheck = $Check
if ($resolvedCheck -eq "Body") { $resolvedCheck = "body_traits_check" }

if ($resolvedCheck -eq "All") {
    if (-not (Run-GenVerifier)) { $overallFail = $true }
    foreach ($name in $genericChecks) {
        if (-not (Run-GenericCheck $name)) { $overallFail = $true }
    }
} elseif ($resolvedCheck -eq "Gen") {
    if (-not (Run-GenVerifier)) { $overallFail = $true }
} elseif ($genericChecks -contains $resolvedCheck) {
    if (-not (Run-GenericCheck $resolvedCheck)) { $overallFail = $true }
} else {
    Write-Host "Неизвестное значение -Check: '$Check'." -ForegroundColor Red
    Write-Host "Доступно: All, Gen, $([string]::Join(', ', $genericChecks))"
    exit 2
}

Write-Host ""
if ($overallFail) {
    Write-Host "=== ИТОГ: ЕСТЬ ПРОВАЛЫ ===" -ForegroundColor Red
    exit 1
} else {
    Write-Host "=== ИТОГ: ВСЁ ОК ===" -ForegroundColor Green
    exit 0
}

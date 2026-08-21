<#
.SYNOPSIS
    Прогоняет headless sanity-check'и Astral Genesis и печатает единый вердикт.

.DESCRIPTION
    Оборачивает два существующих dev-сценария в консистентный CI-подобный запуск:
      - dev/body_traits_check.tscn — 24 ассерта модели характеристик тела
        (захват/изгнание/распад); сам возвращает exit code.
      - dev/gen_verifier.tscn — генератор графа + библиотека пресетов на
        SEED_COUNT сидах; ничего не возвращает и не квитится сам, поэтому
        вывод парсится на "недобор дверей" / "недостижимо" / "проблем".

    Ни то, ни другое не подменяет ручной плейтест — см. SKILL.md, раздел
    «Что headless-проверки не ловят».

.PARAMETER GodotPath
    Путь к Godot-исполняемому файлу. По умолчанию — известный путь на машине
    разработчика (console-сборка: обычная detach'ится и не печатает в консоль).

.PARAMETER Check
    Какие проверки прогнать: All (по умолчанию), Body, Gen.

.PARAMETER SkipSubmoduleCheck
    Не проверять/не инициализировать addons/gecs. Использовать, если уже
    заведомо инициализирован — проверка дешёвая, но пропустить можно.

.EXAMPLE
    ./run_gameplay_checks.ps1
    Прогоняет обе проверки известным Godot.

.EXAMPLE
    ./run_gameplay_checks.ps1 -Check Body -GodotPath "D:\Godot\Godot_v4.7.1-stable_win64_console.exe"
#>
param(
    [string]$GodotPath = "C:\Program Files\Godot Engine\Godot_v4.7.1-stable_win64_console.exe",
    [ValidateSet("All", "Body", "Gen")]
    [string]$Check = "All",
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
Write-Host "Репозиторий: $RepoRoot"

if (-not (Test-Path $GodotPath)) {
    # Известный путь не подошёл — поищем любую console-сборку Godot 4.
    $fallback = Get-ChildItem "C:\Program Files\Godot Engine\" -Filter "*_console.exe" -ErrorAction SilentlyContinue |
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

function Run-BodyTraitsCheck {
    Write-Host "`n=== body_traits_check ==="
    & $GodotPath --headless --path $RepoRoot "res://dev/body_traits_check.tscn" --quit-after 300
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Host "FAIL: body_traits_check вышел с кодом $code (см. вывод выше — строки 'FAIL')" -ForegroundColor Red
        return $false
    }
    Write-Host "OK: body_traits_check — все ассерты прошли." -ForegroundColor Green
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

if ($Check -eq "All" -or $Check -eq "Body") {
    if (-not (Run-BodyTraitsCheck)) { $overallFail = $true }
}
if ($Check -eq "All" -or $Check -eq "Gen") {
    if (-not (Run-GenVerifier)) { $overallFail = $true }
}

Write-Host ""
if ($overallFail) {
    Write-Host "=== ИТОГ: ЕСТЬ ПРОВАЛЫ ===" -ForegroundColor Red
    exit 1
} else {
    Write-Host "=== ИТОГ: ВСЁ ОК ===" -ForegroundColor Green
    exit 0
}

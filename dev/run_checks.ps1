<#
.SYNOPSIS
    Прогоняет headless sanity-check'и Astral Genesis и печатает единый вердикт.

.DESCRIPTION
    Оборачивает dev-сценарии в консистентный CI-подобный запуск: любой
    dev/*_check.tscn (body_traits_check, stat_modifiers_check, …)
    подхватывается АВТОМАТИЧЕСКИ — он сам печатает ok/FAIL по каждому ассерту и
    выходит нужным кодом (см. SKILL.md, §«Как писать проверку»). Ничего
    регистрировать вручную не нужно — новый файл с этим суффиксом подхватится сам
    при следующем прогоне.

    Особых случаев нет. Последним был dev/gen_verifier.tscn, чей вывод раннер
    разбирал регулярками и два числа из четырёх только печатал; его инварианты
    переехали ассертами в corridor_graph_check.

    Прогон не подменяет ручной плейтест — см. SKILL.md, раздел
    «Чек-лист ручного плейтеста».

.PARAMETER GodotPath
    Путь к Godot-исполняемому файлу. По умолчанию — переменная окружения GODOT
    (так его передаёт CI), иначе известный путь на машине разработчика
    (console-сборка: обычная detach'ится и не печатает в консоль), иначе
    `godot` из PATH.

.PARAMETER Check
    Какую проверку прогнать: "All" (по умолчанию, всё) либо имя файла любого
    dev/*_check.tscn без расширения (например "body_traits_check"). "Body"
    остаётся алиасом "body_traits_check" для обратной совместимости.

.PARAMETER ListChecks
    Только напечатать, какие dev/*_check.tscn найдены, и выйти — без запуска
    Godot. Полезно после того как в dev/ добавился новый сценарий.

.PARAMETER SkipSubmoduleCheck
    Не проверять/не инициализировать addons/gecs. Использовать, если уже
    заведомо инициализирован — проверка дешёвая, но пропустить можно.

.EXAMPLE
    ./dev/run_checks.ps1
    Прогоняет все найденные dev/*_check.tscn известным Godot.

.EXAMPLE
    ./dev/run_checks.ps1 -Check body_traits_check -GodotPath "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"

.EXAMPLE
    ./dev/run_checks.ps1 -ListChecks
    Показывает, что сейчас будет прогнано под "-Check All", без запуска.
#>
param(
    [string]$GodotPath = $(if ($env:GODOT) { $env:GODOT } else { "C:\Program Files\Godot Engine\4.7.2\Godot_v4.7.2-stable_win64_console.exe" }),
    [string]$Check = "All",
    [switch]$ListChecks,
    [switch]$SkipSubmoduleCheck
)

$ErrorActionPreference = "Stop"

# Раннер лежит в dev/, рядом с самими проверками: один раннер на разработчика и
# CI. Раньше он жил в папке скилла gameplay-testing, и CI было нечем его звать.
function Find-RepoRoot {
    $dir = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path (Join-Path $dir "project.godot"))) {
        throw "Не найден project.godot в $dir — раннер должен лежать в dev/ репозитория."
    }
    return $dir
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
    Get-GenericChecks | ForEach-Object { Write-Host $_ }
    exit 0
}

Write-Host "Репозиторий: $RepoRoot"

if (-not (Test-Path $GodotPath)) {
    # Известный путь не подошёл — поищем любую console-сборку Godot 4, а на
    # Linux/macOS — godot из PATH.
    $fallback = Get-ChildItem "C:\Program Files\Godot Engine\" -Filter "*_console.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $fallback) {
        $fallback = Get-Command godot -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    }
    if ($fallback) {
        Write-Host "Godot по умолчанию не найден, использую: $fallback"
        $GodotPath = $fallback
    } else {
        throw "Godot не найден ни по '$GodotPath', ни в 'C:\Program Files\Godot Engine\', ни в PATH. Передайте -GodotPath или GODOT."
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
    # Вывод Godot обязательно захватывать, а не пускать в поток успеха функции:
    # иначе `return $false` возвращается вместе со всеми напечатанными строками,
    # вызывающий получает непустой массив, `-not $array` даёт $false — и провал
    # проверки не засчитывается. Так молча терялся КАЖДЫЙ упавший *_check.
    # --quit-after считает кадры ОТРИСОВКИ, а не физики: в headless их выходит в
    # разы больше, чем физкадров, поэтому запас берётся щедрый. Упереться в него
    # всё равно можно, и это молчаливый провал — см. проверку итоговой строки ниже.
    $output = & $GodotPath --headless --path $RepoRoot "res://dev/$Name.tscn" --quit-after 6000 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) {
        Write-Host "FAIL: $Name вышел с кодом $code (см. вывод выше — строки 'FAIL')" -ForegroundColor Red
        return $false
    }
    # Оборванная проверка выходит с НУЛЁМ: до `get_tree().quit()` она не дошла,
    # движок закрылся сам по --quit-after. По коду возврата это неотличимо от
    # успеха, поэтому итоговую строку проверка обязана напечатать сама — её
    # отсутствие и есть признак обрыва.
    $summary = $output | Select-String -Pattern "=== ИТОГ:" -SimpleMatch | Select-Object -Last 1
    if (-not $summary) {
        Write-Host "FAIL: $Name не напечатал итоговую строку — прогон оборван, а не пройден" -ForegroundColor Red
        return $false
    }
    # Код 0 при провалах тоже бывает: проверка, чей сценарий сменил сцену
    # (change_scene_to_file) до её собственного quit(), выходит с кодом того,
    # кто закрыл движок последним. Итоговая строка при этом честная — ей и верим.
    if ($summary.Line -match "провалов=([1-9]\d*)") {
        Write-Host "FAIL: $Name — провалов $($Matches[1]) при коде выхода 0" -ForegroundColor Red
        return $false
    }
    Write-Host "OK: $Name — все ассерты прошли." -ForegroundColor Green
    return $true
}

$genericChecks = Get-GenericChecks

# "Body" — алиас "body_traits_check" для обратной совместимости с тем, как
# параметр назывался до автообнаружения (см. SKILL.md, старые примеры).
$resolvedCheck = $Check
if ($resolvedCheck -eq "Body") { $resolvedCheck = "body_traits_check" }

if ($resolvedCheck -eq "All") {
    foreach ($name in $genericChecks) {
        if (-not (Run-GenericCheck $name)) { $overallFail = $true }
    }
} elseif ($genericChecks -contains $resolvedCheck) {
    if (-not (Run-GenericCheck $resolvedCheck)) { $overallFail = $true }
} else {
    Write-Host "Неизвестное значение -Check: '$Check'." -ForegroundColor Red
    Write-Host "Доступно: All, $([string]::Join(', ', $genericChecks))"
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

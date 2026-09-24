#Requires -Version 7.0
<#
.SYNOPSIS
	Приводит настройки импорта всех .glb проекта к правилам пайплайна.

.DESCRIPTION
	Импортёр Godot пересобирает сцену из .glb на каждом реимпорте, и всё, что
	настроено руками внутри импортированной ветки, теряется. Материал выживает
	ровно одним способом — если он вынесен во внешний .tres, а в .import стоит
	явная ссылка на него.

	Скрипт делает две вещи:

	1. Проставляет ССЫЛКИ на внешние материалы. Имена материалов читаются прямо
	   из glTF-чанка .glb; для каждого, у кого в папке материалов лежит .tres с
	   тем же именем, пишется use_external с реальным путём. Это единственная
	   надёжная часть механизма: проверено — при полной пересборке .glb такая
	   ссылка выживает нетронутой.

	2. Включает `materials/extract = Extract Once` как БУТСТРАП для материалов,
	   у которых .tres ещё нет: движок создаст файл (существующий он не
	   перезаписывает никогда). Полагаться на извлечение как на постоянный
	   механизм нельзя — измерено, что при отсутствующей ссылке и уже
	   существующем .tres оно записывает use_external с ПУСТЫМИ путями, и
	   материал сваливается во внутренний. Поэтому пункт 1 обязателен, а пункт 2
	   лишь заводит новые файлы; ссылку на них добавит следующий прогон скрипта.

	Заодно выключается извлечение встроенных изображений: дефолтное
	«Extract Textures» высыпало текстуры рядом с .glb при каждом реимпорте.

	Скрипт идемпотентен и уважает ручные настройки: непустой extract_path,
	непустой import_script и ссылка, уже указывающая на существующий файл, не
	затираются. Всё прочее содержимое .import — включая раздел "meshes" в
	_subresources — сохраняется как есть.

.PARAMETER Root
	Корень проекта. По умолчанию — папка над этим скриптом.

.PARAMETER MaterialDir
	res://-путь папки с материалами: и куда извлекать новые, и где искать .tres
	для ссылок. По умолчанию общий на проект. Ассету, который дорос до
	собственных материалов, путь ставится в редакторе — скрипт увидит, что
	extract_path непустой, и не тронет его; ссылки для такого ассета тоже
	останутся своими, пока указывают на существующие файлы.

.PARAMETER ImportScript
	res://-путь скрипта постимпорта для файлов, у которых он ещё не задан.
	Пустая строка — не проставлять никому.

.PARAMETER DryRun
	Показать, что изменилось бы, и ничего не писать.

.EXAMPLE
	pwsh dev/fix_import_settings.ps1 -DryRun

.EXAMPLE
	pwsh dev/fix_import_settings.ps1

.NOTES
	Правка .import сама пересборку не запускает — после прогона нужен реимпорт:
	открыть проект в редакторе либо
	`Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`.
	Для НОВОГО ассета с новым материалом порядок такой: экспорт → импорт
	(движок создаст .tres) → прогон скрипта (проставит ссылку) → реимпорт.
	Почему настройки именно такие — «Blender-Godot пайплайн» в docs/.
#>

[CmdletBinding()]
param(
	[string]$Root = (Split-Path -Parent $PSScriptRoot),
	[string]$MaterialDir = "res://assets/materials",
	[string]$ImportScript = "res://addons/godot_pipeline/collision_post_import.gd",
	[switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Note([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Fail([string]$Text) { throw $Text }

# Значения перечислений ResourceImporterScene. Держим числами, потому что именно
# числа лежат в .import, а подписи в редакторе переводятся и меняются.
$EXTRACT_ONCE = '1'      # 0 — Keep Internal, 2 — Extract and Overwrite
$EXTRACT_TRES = '0'      # 0 — Text (*.tres), 1 — Binary (*.res), 2 — *.material
$DISCARD_TEXTURES = '0'  # 1 — Extract Textures (дефолт движка), 2/3 — Embed


# --- работа с ключами [params] ---------------------------------------------

function Get-ImportParam {
	param([System.Collections.Generic.List[string]]$Lines, [string]$Key)

	$prefix = "$Key="
	foreach ($line in $Lines) {
		if ($line.StartsWith($prefix)) { return $line.Substring($prefix.Length) }
	}
	return $null
}


function Set-ImportParam {
	param(
		[System.Collections.Generic.List[string]]$Lines,
		[string]$Key,
		[string]$Value,
		# Force — ставить всегда; IfEmpty — только поверх пустой строки;
		# IfMissing — только если ключа в файле нет вовсе.
		[ValidateSet('Force', 'IfEmpty', 'IfMissing')]
		[string]$Mode = 'Force'
	)

	$prefix = "$Key="
	for ($i = 0; $i -lt $Lines.Count; $i++) {
		if (-not $Lines[$i].StartsWith($prefix)) { continue }

		$old = $Lines[$i].Substring($prefix.Length)
		if ($old -eq $Value) { return $null }
		if ($Mode -eq 'IfMissing') { return $null }
		if ($Mode -eq 'IfEmpty' -and $old -ne '""') { return $null }

		$Lines[$i] = "$Key=$Value"
		return "$Key`: $old -> $Value"
	}

	# Ключа нет (файл от более старой версии Godot). Вставляем перед
	# _subresources — там его держит сам движок, и глазами потом легче сверять;
	# порядок ключей в .import движку безразличен.
	$at = $Lines.Count
	for ($i = 0; $i -lt $Lines.Count; $i++) {
		if ($Lines[$i].StartsWith('_subresources=')) { $at = $i; break }
	}
	$Lines.Insert($at, "$Key=$Value")
	return "$Key`: (ключа не было) -> $Value"
}


# --- чтение имён материалов из .glb ----------------------------------------

function Get-GltfMaterialNames([string]$Path) {
	$json = $null
	if ($Path.EndsWith('.gltf', [StringComparison]::OrdinalIgnoreCase)) {
		$json = [IO.File]::ReadAllText($Path)
	} else {
		# JSON-чанк .glb лежит открытым текстом сразу после 20-байтового
		# заголовка, его длина записана в байтах 12..15. Читать файл целиком и
		# искать регуляркой нельзя: следом идёт бинарный буфер геометрии, и
		# совпадения в нём выглядят как настоящие имена.
		$bytes = [IO.File]::ReadAllBytes($Path)
		if ($bytes.Length -lt 20) { return @() }
		$length = [int][Math]::Min([BitConverter]::ToUInt32($bytes, 12), $bytes.Length - 20)
		$json = [Text.Encoding]::UTF8.GetString($bytes, 20, $length)
	}

	try { $doc = $json | ConvertFrom-Json } catch { return @() }
	if ($null -eq $doc.materials) { return @() }
	return @($doc.materials | ForEach-Object { $_.name } | Where-Object { $_ })
}


# --- работа с блоком _subresources -----------------------------------------

## Индексы строк [начало, конец] блока, открывающегося на строке $Start.
## Godot пишет _subresources без отступов и по одному токену на строку, так что
## хватает подсчёта скобок вне кавычек.
function Get-BlockRange {
	param([System.Collections.Generic.List[string]]$Lines, [int]$Start)

	$depth = 0
	for ($i = $Start; $i -lt $Lines.Count; $i++) {
		$inQuotes = $false
		foreach ($ch in $Lines[$i].ToCharArray()) {
			if ($ch -eq '"') { $inQuotes = -not $inQuotes; continue }
			if ($inQuotes) { continue }
			if ($ch -eq '{') { $depth++ }
			elseif ($ch -eq '}') { $depth-- }
		}
		if ($depth -le 0) { return @($Start, $i) }
	}
	return @($Start, $Lines.Count - 1)
}


function Format-MaterialsSection([hashtable]$Entries, [bool]$Trailing) {
	$out = [System.Collections.Generic.List[string]]::new()
	$out.Add('"materials": {')
	$names = @($Entries.Keys | Sort-Object)
	for ($i = 0; $i -lt $names.Count; $i++) {
		$name = $names[$i]
		$out.Add('"' + $name + '": {')
		$keys = @($Entries[$name].Keys | Sort-Object)
		for ($k = 0; $k -lt $keys.Count; $k++) {
			$value = $Entries[$name][$keys[$k]]
			$text = if ($value -is [bool]) { if ($value) { 'true' } else { 'false' } } else { '"' + $value + '"' }
			$out.Add('"' + $keys[$k] + '": ' + $text + $(if ($k -lt $keys.Count - 1) { ',' } else { '' }))
		}
		$out.Add('}' + $(if ($i -lt $names.Count - 1) { ',' } else { '' }))
	}
	$out.Add('}' + $(if ($Trailing) { ',' } else { '' }))
	return $out
}


## Проставляет use_external для материалов из $Links (имя -> res://путь).
## Возвращает список описаний изменений.
function Set-ExternalMaterials {
	param(
		[System.Collections.Generic.List[string]]$Lines,
		[hashtable]$Links,
		[string]$ProjectRoot
	)

	$changes = @()
	if ($Links.Count -eq 0) { return $changes }

	$subIndex = -1
	for ($i = 0; $i -lt $Lines.Count; $i++) {
		if ($Lines[$i].StartsWith('_subresources=')) { $subIndex = $i; break }
	}
	if ($subIndex -lt 0) {
		$Lines.Add('_subresources={}')
		$subIndex = $Lines.Count - 1
	}

	# Что уже записано: читаем существующий раздел "materials" как JSON — там
	# только строки и bool, так что разбор безопасен. Раздел "meshes" не
	# трогаем вообще: в нём лежат числа с плавающей точкой, и пересборка их
	# текста меняла бы тип параметра (20.0 -> 20).
	$range = Get-BlockRange $Lines $subIndex
	$region = $Lines[$range[0]..$range[1]]
	$matStart = -1
	for ($i = 0; $i -lt $region.Count; $i++) {
		if ($region[$i] -eq '"materials": {') { $matStart = $range[0] + $i; break }
	}

	$entries = @{}
	$matRange = $null
	if ($matStart -ge 0) {
		$matRange = Get-BlockRange $Lines $matStart
		$text = ($Lines[$matRange[0]..$matRange[1]] -join "`n").TrimEnd(',')
		try {
			$parsed = "{$text}" | ConvertFrom-Json
			foreach ($property in $parsed.materials.PSObject.Properties) {
				$bag = @{}
				foreach ($inner in $property.Value.PSObject.Properties) { $bag[$inner.Name] = $inner.Value }
				$entries[$property.Name] = $bag
			}
		} catch {
			Write-Warning "не разобрал раздел materials, пропускаю ссылки: $($_.Exception.Message)"
			return $changes
		}
	}

	$dirty = $false
	foreach ($name in $Links.Keys) {
		$target = $Links[$name]
		$existing = $entries[$name]
		if ($null -ne $existing) {
			$current = [string]$existing['use_external/path']
			# Своя ручная ссылка на существующий файл — не наше дело.
			if ($current -and $current -ne '') {
				$abs = if ($current.StartsWith('res://')) {
					Join-Path $ProjectRoot ($current -replace '^res://', '')
				} else { $null }
				if ($null -eq $abs -or (Test-Path $abs)) { continue }
			}
			$changes += "материал $name`: ссылка была пустой/битой -> $target"
		} else {
			$changes += "материал $name`: ссылка проставлена -> $target"
			$existing = @{}
			$entries[$name] = $existing
		}
		$existing['use_external/enabled'] = $true
		$existing['use_external/path'] = $target
		$existing['use_external/fallback_path'] = $target
		$dirty = $true
	}
	if (-not $dirty) { return $changes }

	# Приведение к [string[]] обязательно: из функции List[string] возвращается
	# развёрнутым в Object[], и InsertRange такой аргумент не принимает.
	$block = [string[]](Format-MaterialsSection $entries ($null -ne $matRange -and $matRange[1] -lt $range[1]))
	if ($null -ne $matRange) {
		$Lines.RemoveRange($matRange[0], $matRange[1] - $matRange[0] + 1)
		$Lines.InsertRange($matRange[0], $block)
	} elseif ($Lines[$subIndex] -eq '_subresources={}') {
		$Lines[$subIndex] = '_subresources={'
		$Lines.InsertRange($subIndex + 1, $block)
		$Lines.Insert($subIndex + 1 + $block.Count, '}')
	} else {
		# Есть другие разделы — вставляем "materials" первым, с запятой.
		$block = [string[]](Format-MaterialsSection $entries $true)
		$Lines.InsertRange($subIndex + 1, $block)
	}
	return $changes
}


function Resolve-ResPath([string]$ProjectRoot, [string]$ResPath) {
	return Join-Path $ProjectRoot ($ResPath -replace '^res://', '' -replace '/', [IO.Path]::DirectorySeparatorChar)
}


## Где лежит .tres материала: от самого частного к общему.
##
## Ассет, доросший до личного материала (§1), держит его у себя — искать надо
## сначала там, иначе скрипт объявит такой материал потерянным и полезет
## проставлять ссылку на общую папку, где его нет.
function Find-MaterialFile {
	param(
		[string]$ProjectRoot,
		[string]$AssetDir,       # папка, где лежит .glb
		[string]$Name,
		[string]$GlobalDir       # res://-путь общей папки
	)

	$assetsRoot = (Join-Path $ProjectRoot 'assets').TrimEnd('\', '/')
	$dir = $AssetDir
	while ($dir -and $dir.Length -ge $assetsRoot.Length) {
		foreach ($candidate in @((Join-Path $dir "materials\$Name.tres"), (Join-Path $dir "$Name.tres"))) {
			if (Test-Path $candidate) {
				$rel = $candidate.Substring($ProjectRoot.Length).TrimStart('\', '/').Replace('\', '/')
				return "res://$rel"
			}
		}
		if ($dir -eq $assetsRoot) { break }
		$dir = Split-Path -Parent $dir
	}

	$global = "$GlobalDir/$Name.tres"
	if (Test-Path (Resolve-ResPath $ProjectRoot $global)) { return $global }
	return $null
}


# --- подготовка ------------------------------------------------------------

if (-not (Test-Path $Root)) { Fail "Не найден корень проекта: $Root" }
$Root = (Resolve-Path $Root).Path
if (-not (Test-Path (Join-Path $Root 'project.godot'))) {
	Fail "В $Root нет project.godot — это не корень проекта Godot."
}

$assetsDir = Join-Path $Root 'assets'
if (-not (Test-Path $assetsDir)) { Fail "Не найдена папка assets в $Root" }

if ($MaterialDir -notmatch '^res://') { Fail "MaterialDir должен начинаться с res:// — получено «$MaterialDir»" }
$MaterialDir = $MaterialDir.TrimEnd('/')
$materialAbs = Resolve-ResPath $Root $MaterialDir
if (-not (Test-Path $materialAbs)) {
	# Не создаём молча: пустая папка, появившаяся из-за опечатки в пути,
	# выглядит как рабочая настройка, а материалы уедут не туда.
	Fail "Папки $MaterialDir нет на диске ($materialAbs). Создай её или укажи -MaterialDir."
}

if ($ImportScript) {
	if ($ImportScript -notmatch '^res://') { Fail "ImportScript должен начинаться с res:// — получено «$ImportScript»" }
	$scriptAbs = Resolve-ResPath $Root $ImportScript
	if (-not (Test-Path $scriptAbs)) {
		Fail "Скрипта постимпорта нет на диске: $ImportScript ($scriptAbs). Поставь его из плагина или передай -ImportScript ''."
	}
}

Write-Step "Настройки импорта: $Root"
Write-Note "материалы -> $MaterialDir (extract_path — только там, где не задан)"
Write-Note $(if ($ImportScript) { "скрипт постимпорта -> $ImportScript (только там, где не задан)" } else { "скрипт постимпорта не трогаем" })
if ($DryRun) { Write-Note "режим -DryRun: файлы не пишутся" }

$importFiles = Get-ChildItem $assetsDir -Recurse -File |
	Where-Object { $_.Name -like '*.glb.import' -or $_.Name -like '*.gltf.import' } |
	Sort-Object FullName
if ($importFiles.Count -eq 0) { Fail "В $assetsDir не нашлось ни одного *.glb.import" }

# --- обход -----------------------------------------------------------------

$touched = 0
$orphans = @()
$missingMaterials = [System.Collections.Generic.SortedSet[string]]::new()

foreach ($file in $importFiles) {
	$source = $file.FullName -replace '\.import$', ''
	if (-not (Test-Path $source)) {
		# .import без своего .glb Godot всё равно однажды удалит, но пока он тут,
		# правка в нём только путает при сверке глазами.
		$orphans += $file.FullName.Replace("$Root$([IO.Path]::DirectorySeparatorChar)", '')
		continue
	}

	$raw = [IO.File]::ReadAllText($file.FullName)
	$newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
	$lines = [System.Collections.Generic.List[string]]($raw -split "`r`n|`n")

	$changes = @()

	# Extract and Overwrite (2) выбирают вручную и осознанно — понизить его
	# значило бы тихо отменить чужое решение.
	if ((Get-ImportParam $lines 'materials/extract') -eq '2') {
		Write-Note "$($file.Name): materials/extract=2 (Overwrite) — оставляю как есть"
	} else {
		$changes += Set-ImportParam $lines 'materials/extract' $EXTRACT_ONCE
	}

	$changes += Set-ImportParam $lines 'materials/extract_format' $EXTRACT_TRES -Mode IfMissing
	$changes += Set-ImportParam $lines 'materials/extract_path' "`"$MaterialDir`"" -Mode IfEmpty
	$changes += Set-ImportParam $lines 'gltf/embedded_image_handling' $DISCARD_TEXTURES
	if ($ImportScript) {
		$changes += Set-ImportParam $lines 'import_script/path' "`"$ImportScript`"" -Mode IfEmpty
	}

	# Ссылки на внешние материалы: только для тех, чей .tres реально есть.
	# Материал без файла оставляем движку — он создаст его на реимпорте
	# (Extract Once), а ссылку добавит следующий прогон скрипта.
	$links = @{}
	foreach ($name in (Get-GltfMaterialNames $source)) {
		$found = Find-MaterialFile $Root ([IO.Path]::GetDirectoryName($source)) $name $MaterialDir
		if ($found) {
			$links[$name] = $found
		} else {
			$missingMaterials.Add("$name (нужен для $($file.Name -replace '\.import$',''))") | Out-Null
		}
	}
	$changes += Set-ExternalMaterials $lines $links $Root

	$changes = $changes | Where-Object { $_ }
	if ($changes.Count -eq 0) { continue }

	$touched++
	Write-Host "  $($source.Replace("$Root$([IO.Path]::DirectorySeparatorChar)", ''))" -ForegroundColor White
	$changes | ForEach-Object { Write-Note $_ }

	if (-not $DryRun) {
		# Пишем UTF-8 без BOM и родными переводами строк: .import — текстовый
		# файл под `* text=auto eol=lf`, и лишний BOM или CRLF в нём показался бы
		# в diff'е у каждого файла.
		[IO.File]::WriteAllText($file.FullName, ($lines -join $newline), [Text.UTF8Encoding]::new($false))
	}
}

# --- итог ------------------------------------------------------------------

Write-Step "Итог"
Write-Host "    файлов просмотрено: $($importFiles.Count)"
Write-Host "    файлов изменено:    $touched" -ForegroundColor $(if ($touched) { 'Yellow' } else { 'Green' })

if ($orphans.Count -gt 0) {
	Write-Host ""
	Write-Warning "Пропущены .import без своего .glb ($($orphans.Count)):"
	$orphans | ForEach-Object { Write-Note $_ }
}

if ($missingMaterials.Count -gt 0) {
	Write-Host ""
	Write-Host "Материалы без .tres в $MaterialDir — ссылку поставить пока не на что:" -ForegroundColor Yellow
	$missingMaterials | ForEach-Object { Write-Note $_ }
	Write-Note "Реимпорт создаст файлы (Extract Once); прогони скрипт ещё раз, чтобы проставить ссылки."
}

if ($touched -gt 0) {
	Write-Host ""
	if ($DryRun) {
		Write-Host "Это был -DryRun. Прогнать по-настоящему:" -ForegroundColor Yellow
		Write-Host "    pwsh dev/fix_import_settings.ps1" -ForegroundColor Yellow
	} else {
		Write-Host "Теперь нужен реимпорт — правка .import сама его не запускает:" -ForegroundColor Yellow
		Write-Host "    открыть проект в редакторе, либо" -ForegroundColor Yellow
		Write-Host "    & 'C:\Program Files\Godot Engine\4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import" -ForegroundColor Yellow
	}
}

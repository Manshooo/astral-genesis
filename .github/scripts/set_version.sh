#!/usr/bin/env bash
# Проставляет версию во все места, где она продублирована в репозитории:
#   project.godot      — config/version, попадает в метаданные exe и доступен
#                        из игры через ProjectSettings("application/config/version")
#   export_presets.cfg — имена файлов локального экспорта из редактора
#
# Единственный источник правды о версии — имя ветки release/vX.Y.Z; этот скрипт
# вызывается из .github/workflows/release.yml, руками его звать не нужно.
# Ручной вызов (например, чтобы локально собрать сборку с правильным именем):
#   bash .github/scripts/set_version.sh 0.5.0

set -euo pipefail

version="${1:-}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Использование: set_version.sh X.Y.Z (получено: '${version}')" >&2
	exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="${root}/project.godot"
presets="${root}/export_presets.cfg"

sed -i -E \
	"s|^config/version=\".*\"$|config/version=\"${version}\"|" \
	"$project"

sed -i -E \
	-e "s|^export_path=\"builds/windows/.*\"$|export_path=\"builds/windows/astral-genesis-v${version}-windows-x86_64.exe\"|" \
	-e "s|^export_path=\"builds/linux/.*\"$|export_path=\"builds/linux/astral-genesis-v${version}-linux-x86_64.zip\"|" \
	"$presets"

# sed молча ничего не делает, если якорь не совпал: проверяем, что версия
# действительно проставлена, иначе релиз уедет со старым номером.
grep -qF "config/version=\"${version}\"" "$project" \
	|| { echo "Не удалось проставить config/version в project.godot" >&2; exit 1; }
grep -qF "builds/windows/astral-genesis-v${version}-windows-x86_64.exe" "$presets" \
	|| { echo "Не удалось проставить export_path для Windows" >&2; exit 1; }
grep -qF "builds/linux/astral-genesis-v${version}-linux-x86_64.zip" "$presets" \
	|| { echo "Не удалось проставить export_path для Linux" >&2; exit 1; }

echo "Версия ${version} проставлена в project.godot и export_presets.cfg"

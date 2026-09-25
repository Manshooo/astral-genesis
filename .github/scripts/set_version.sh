#!/usr/bin/env bash
# Проставляет номер версии во все места, где он продублирован в репозитории:
#   project.godot      — config/version: его показывает сама игра (угол главного
#                        меню, отладочный оверлей), из него же Godot берёт версию
#                        в метаданные .exe
#   export_presets.cfg — имена файлов локального экспорта из редактора и числовая
#                        версия Windows-файла у не-релизной сборки
#
# Номер бывает двух видов:
#   X.Y.Z             — версия, которая разрабатывается или выпускается. Её
#                       коммитят: руками раз в начале цикла версии и ботом
#                       release.yml, если релиз выходит под другим номером.
#   X.Y.Z-dev.N+HASH  — не-релизная сборка (номер считает build_version.sh).
#                       Вписывается только на время сборки и не коммитится.
#
#   bash .github/scripts/set_version.sh 0.8.0

set -euo pipefail

version="${1:-}"

if [[ ! "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-dev\.([0-9]+)\+[0-9a-f]+)?$ ]]; then
	echo "Использование: set_version.sh X.Y.Z | X.Y.Z-dev.N+HASH (получено: '${version}')" >&2
	exit 1
fi

# Godot пускает в метаданные .exe только цифры и точки: на «0.7.0-dev.3+abc»
# он лишь предупреждает и пишет 1.0.0.0 (EditorExportPreset::get_version) —
# свойства файла врали бы молча. Поэтому у не-релизной сборки числовая версия
# задаётся явно, а номер сборки идёт четвёртым полем, которое у Windows для
# этого и есть. У релиза поле пустое: Godot сам выведет X.Y.Z.0 из config/version.
windows_version=""
if [ -n "${BASH_REMATCH[3]}" ]; then
	windows_version="${BASH_REMATCH[1]}.${BASH_REMATCH[3]}"
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
	-e "s|^application/file_version=\".*\"$|application/file_version=\"${windows_version}\"|" \
	-e "s|^application/product_version=\".*\"$|application/product_version=\"${windows_version}\"|" \
	"$presets"

# sed молча ничего не делает, если якорь не совпал: проверяем, что версия
# действительно проставлена, иначе сборка уедет со старым номером.
grep -qF "config/version=\"${version}\"" "$project" \
	|| { echo "Не удалось проставить config/version в project.godot" >&2; exit 1; }
grep -qF "builds/windows/astral-genesis-v${version}-windows-x86_64.exe" "$presets" \
	|| { echo "Не удалось проставить export_path для Windows" >&2; exit 1; }
grep -qF "builds/linux/astral-genesis-v${version}-linux-x86_64.zip" "$presets" \
	|| { echo "Не удалось проставить export_path для Linux" >&2; exit 1; }
grep -qF "application/file_version=\"${windows_version}\"" "$presets" \
	|| { echo "Не удалось проставить application/file_version для Windows" >&2; exit 1; }
grep -qF "application/product_version=\"${windows_version}\"" "$presets" \
	|| { echo "Не удалось проставить application/product_version для Windows" >&2; exit 1; }

echo "Версия ${version} проставлена в project.godot и export_presets.cfg"

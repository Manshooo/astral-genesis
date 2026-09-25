#!/usr/bin/env bash
# Печатает номер, под которым собирается коммит [REV] (по умолчанию HEAD):
#   0.7.0                — REV и есть выпущенный v0.7.0, а в project.godot 0.7.0
#   0.7.0-dev.33+fc91d3c — любой другой коммит: разрабатывается 0.7.0 (из
#                          project.godot), с прошлого релиза прошло 33 коммита,
#                          сборка — с fc91d3c
#
# Снапшотов -devN/-betaN у проекта нет, и номер не обещает ничего сверх того,
# что есть: по нему видно, из какого коммита сборка, а по N — какая из двух
# сборок новее. -dev ставит её раньше релиза 0.7.0 при сортировке по semver,
# а хэш — метаданные сборки, в порядке не участвуют.
#
# Нужна история с тегами vX.Y.Z: в CI — checkout с fetch-depth: 0, локально
# обычный клон (в облачной сессии теги подтягивает SessionStart-хук).
#
#   bash .github/scripts/build_version.sh
#   bash .github/scripts/build_version.sh "$PR_HEAD_SHA"

set -euo pipefail

rev="${1:-HEAD}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

base="$(sed -n -E 's/^config\/version="([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "${root}/project.godot" | head -n 1)"
if [ -z "$base" ]; then
	echo "config/version в project.godot не вида X.Y.Z — номер сборки не из чего собрать" >&2
	exit 1
fi

# --match отсекает исторические alpha-v0.x.y; --long даёт «-0-g<хэш>» и на
# самом теге, так что разбор один на оба случая.
if ! described="$(git -C "$root" describe --tags --long --abbrev=7 --match 'v[0-9]*' "$rev" 2>/dev/null)"; then
	echo "В истории ${rev} нет тега vX.Y.Z: клон без тегов или неполный (в CI нужен fetch-depth: 0, локально — git fetch --tags)" >&2
	exit 1
fi

hash="${described##*-g}"
rest="${described%-g*}"
count="${rest##*-}"
tag="${rest%-*}"

if [ "$count" = "0" ] && [ "$tag" = "v${base}" ]; then
	echo "$base"
	exit 0
fi

# Версия уже выпущена, а номер в project.godot не подняли: сборка назвалась бы
# «0.7.0-dev» после релиза 0.7.0 и по semver встала бы раньше него.
if git -C "$root" rev-parse -q --verify "refs/tags/v${base}" >/dev/null; then
	message="v${base} уже выпущена — подними версию: bash .github/scripts/set_version.sh X.Y.Z"
	if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
		echo "::warning::${message}" >&2
	else
		echo "Внимание: ${message}" >&2
	fi
fi

echo "${base}-dev.${count}+${hash}"

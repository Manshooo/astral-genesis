#!/bin/bash
# SessionStart-хук облачной сессии Claude Code: ставит то, без чего в свежем
# контейнере не работают ни ассеты, ни headless-проверки. Клон там голый: вместо
# ассетов LFS-указатели, addons/gecs пуст, тегов нет, Godot и PowerShell нет.
#
# Только в облаке: у разработчика локально Windows со своими Godot и LFS, и там
# хук не делает ничего — CLAUDE_CODE_REMOTE выставляет только облачная сессия.
#
# Каждый шаг сначала смотрит, не сделан ли он уже: хук идёт на каждом старте
# сессии, в том числе после resume и compact, и повторный прогон обязан
# укладываться в секунды, а не качать движок заново.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$root"

# Версия движка — из того же места, что у CI и dev/release.ps1: обновили
# godot-version в godot-setup — хук подтянет новую сам.
godot_version="$(sed -n -E 's/^[[:space:]]*default:[[:space:]]*"([0-9.]+)"[[:space:]]*$/\1/p' .github/actions/godot-setup/action.yml | head -n 1)"
# Обе проверены через прокси облачного окружения (api.github.com им закрыт,
# поэтому версии прибиты и качаются прямыми ссылками на github.com).
git_lfs_version="3.7.0"
pwsh_version="7.5.3"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/astral-genesis"
godot_bin="${cache}/godot-${godot_version}/godot"

log() { echo "[session-start] $*" >&2; }

# Скачать и распаковать архив во временный каталог; путь печатается в stdout.
fetch() {
	local url="$1" tmp
	tmp="$(mktemp -d)"
	curl -fsSL --retry 3 -o "${tmp}/archive" "$url"
	case "$url" in
		*.zip) unzip -q "${tmp}/archive" -d "${tmp}/out" ;;
		*) mkdir -p "${tmp}/out" && tar -xzf "${tmp}/archive" -C "${tmp}/out" ;;
	esac
	echo "${tmp}"
}


install_git_lfs() {
	if git lfs version >/dev/null 2>&1; then
		return
	fi
	log "ставлю git-lfs"
	# apt — первым: пакет короче и сам встаёт в PATH. Индекс в образе бывает
	# пустым, тогда один update; не помогло — бинарник с GitHub.
	if apt-get install -y -qq git-lfs >/dev/null 2>&1 \
		|| { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq git-lfs >/dev/null 2>&1; }; then
		return
	fi
	local tmp
	tmp="$(fetch "https://github.com/git-lfs/git-lfs/releases/download/v${git_lfs_version}/git-lfs-linux-amd64-v${git_lfs_version}.tar.gz")"
	install -m 0755 "${tmp}"/out/git-lfs-*/git-lfs /usr/local/bin/git-lfs
	rm -rf "$tmp"
}


# Только через git-lfs: объект, скачанный мимо него и положенный на место
# указателя, git без фильтра видит изменённым файлом — и следующий коммит увёз
# бы бинарник мимо LFS.
pull_lfs_objects() {
	git lfs install --local >/dev/null
	git lfs pull
}


install_godot() {
	if [ -x "$godot_bin" ]; then
		return
	fi
	log "ставлю Godot ${godot_version}"
	local tmp
	tmp="$(fetch "https://github.com/godotengine/godot/releases/download/${godot_version}-stable/Godot_v${godot_version}-stable_linux.x86_64.zip")"
	mkdir -p "$(dirname "$godot_bin")"
	install -m 0755 "${tmp}/out/Godot_v${godot_version}-stable_linux.x86_64" "$godot_bin"
	rm -rf "$tmp"
}


# dev/run_checks.ps1 — единый прогон проверок, тот же, что у CI, — написан на
# PowerShell; без pwsh в облаке остались бы только проверки по одной.
install_pwsh() {
	if command -v pwsh >/dev/null 2>&1; then
		return
	fi
	log "ставлю PowerShell ${pwsh_version}"
	local dir="${cache}/pwsh-${pwsh_version}" tmp
	tmp="$(fetch "https://github.com/PowerShell/PowerShell/releases/download/v${pwsh_version}/powershell-${pwsh_version}-linux-x64.tar.gz")"
	rm -rf "$dir"
	mkdir -p "$(dirname "$dir")"
	mv "${tmp}/out" "$dir"
	chmod +x "${dir}/pwsh"
	ln -sf "${dir}/pwsh" /usr/local/bin/pwsh
	rm -rf "$tmp"
}


install_git_lfs
pull_lfs_objects
git submodule update --init --recursive --quiet
# Теги — для номера сборки (.github/scripts/build_version.sh считает его от
# последнего vX.Y.Z) и для скилла project-status. Не беда, если не вышло:
# без них не работает только номер, а не сессия.
git fetch --tags --quiet origin || log "теги не подтянулись — номер сборки не посчитать"
install_godot
install_pwsh

ln -sf "$godot_bin" /usr/local/bin/godot
# GODOT читает dev/run_checks.ps1 — так же ему передаёт движок CI.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	echo "export GODOT=\"${godot_bin}\"" >> "$CLAUDE_ENV_FILE"
fi

# Холодный импорт — только в свежем контейнере: замер 25.09 — 33 с (два прохода),
# а проверки гоняет почти каждая сессия, и без импорта они падают. На resume
# .godot/ уже есть, и пересобирать его на каждом старте незачем — после правки
# ассетов импорт добивается той же командой вручную.
imported_note=""
if [ ! -d .godot/imported ]; then
	log "холодный импорт проекта"
	before="$(git -c core.quotePath=false diff --name-only | sort)"
	GODOT="$godot_bin" bash dev/import.sh >&2
	# Холодный импорт переписывает отслеживаемые файлы — 25.09 это меши тел
	# assets/monsters/models/*.res («Баг — тела монстров без текстур в
	# экспортированной сборке», сессия B плана v0.7.0). Сессия не должна
	# начинаться с грязного дерева, которое уедет в первый же коммит, поэтому
	# то, что было чистым до импорта, возвращается из git — но вслух.
	mapfile -t dirtied < <(comm -13 <(printf '%s\n' "$before") <(git -c core.quotePath=false diff --name-only | sort) | sed '/^$/d')
	if [ "${#dirtied[@]}" -gt 0 ]; then
		git checkout -- "${dirtied[@]}"
		imported_note="Холодный импорт переписал отслеживаемые файлы — возвращены из git: ${dirtied[*]}. Это баг импорта, а не правка сессии."
	fi
fi

echo "Облачное окружение готово: Godot ${godot_version} (godot, \$GODOT), ассеты из LFS, addons/gecs, теги, pwsh, импорт в .godot/."
echo "Проверки: pwsh dev/run_checks.ps1. После правки ассетов — повторный импорт: bash dev/import.sh (не godot --import напрямую: многопоточный импорт в headless виснет)."
if [ -n "$imported_note" ]; then
	echo "$imported_note"
fi

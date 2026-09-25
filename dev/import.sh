#!/usr/bin/env bash
# Импорт ресурсов проекта без редактора: холодный (пустой .godot/) или добивающий
# после правки ассетов. Нужен там, где редактора нет, — в облачной сессии
# Claude (его зовёт .claude/hooks/session-start.sh) и в любом headless-окружении.
# Без импорта headless-проверки падают: нет ни ресурсов, ни .godot/extension_list.cfg.
#
# Многопоточный импорт в headless виснет намертво — главный поток ждёт группу
# задач, которая не завершается («Релизы и сборка» → «Почему так»; в облачном
# контейнере 25.09 — на ui.csv и pattern_01.svg, 10 минут без движения).
# Выключить его можно только в project.godot: override.cfg импорт не читает
# (проверено на 4.7.2 — с ним висит точно так же). Поэтому секция дописывается
# на время импорта и срезается trap'ом даже при обрыве — в коммит она уехать не
# должна.
#
#   bash dev/import.sh              # Godot из $GODOT, иначе godot из PATH
#   rm -rf .godot && bash dev/import.sh   # холодный, как в свежем клоне

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT:-godot}"
project="${root}/project.godot"
# Холодный импорт проекта — полминуты; всё, что дольше, — зависание, и лучше
# упасть с внятным сообщением, чем висеть.
timeout_sec="${IMPORT_TIMEOUT:-600}"

backup="$(mktemp)"
cp "$project" "$backup"
trap 'cp "$backup" "$project"; rm -f "$backup"' EXIT
printf '\n[editor]\n\nimport/use_multiple_threads=false\n' >> "$project"

# Первый проход генерирует .uid-файлы, на которые ссылаются сцены, поэтому часть
# зависимостей резолвится только со второго; ошибки парсинга скриптов в первом
# проходе штатны — глобальные классы ещё не просканированы.
for pass in 1 2; do
	set +e
	timeout --foreground "$timeout_sec" "$godot" --headless --path "$root" --import >/dev/null 2>&1
	code=$?
	set -e
	if [ "$code" -eq 124 ]; then
		echo "Импорт (проход ${pass}) не уложился в ${timeout_sec}s — движок завис" >&2
		exit 1
	fi
done

if [ "$code" -ne 0 ]; then
	echo "Импорт завершился с кодом ${code}" >&2
	exit "$code"
fi
echo "Импорт готов: $(find "${root}/.godot/imported" -type f | wc -l) файлов в .godot/imported"

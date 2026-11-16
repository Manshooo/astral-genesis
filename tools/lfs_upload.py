# Выгрузка LFS-объектов мимо системного DNS, когда `git push` виснет на git-lfs.
#
#   python tools/lfs_upload.py [--ref <ветка>] [--ip <адрес S3>]
#   git push
#
# Запуск из корня репозитория, только Python (stdlib) и curl из Git for Windows.
# Одинаковый скрипт лежит в арт-репозитории и в игре.
#
# Почему: с этой машины DNS (VPN) то не отвечает на github-cloud.s3.amazonaws.com
# вовсе, то отдаёт адреса S3, до которых не дойти, — PUT git-lfs висит или рвётся
# по EOF, хотя GitHub (lock, batch) работает. Скрипт делает то же, что git-lfs, но
# адрес S3 берёт сам: DNS-over-HTTPS (dns.google), из ответа — первый адрес, где
# S3 отвечает 403 на анонимный GET (обычный ответ живого S3). Дальше batch API
# GitHub → PUT каждого объекта с --resolve на этот адрес → verify. После этого
# обычный `git push` проходит: объекты уже на сервере, и git-lfs их не шлёт.
#
# Что пушить, решает git-lfs (`git lfs push --dry-run origin <ветка>`). Логин —
# из `git credential fill` для github.com; это работает и для SSH-remote.
# Токены не печатаются: заголовки curl идут через временный -K файл.
import argparse, base64, json, os, subprocess, sys, tempfile, urllib.request

CURL = r"C:\Program Files\Git\mingw64\bin\curl.exe"
HOST = "github-cloud.s3.amazonaws.com"


def git(*a, inp=None):
    return subprocess.run(["git", *a], input=inp, capture_output=True, text=True, check=True).stdout.strip()


def curl(args, headers=None, timeout=300):
    """Код ответа curl; заголовки — через временный файл, чтобы токен не попал в командную строку."""
    cfg = None
    if headers:
        with tempfile.NamedTemporaryFile("w", suffix=".cfg", delete=False, encoding="utf-8") as f:
            for k, v in headers.items():
                f.write(f'header = "{k}: {v}"\n')
            cfg = f.name
    try:
        r = subprocess.run([CURL, "-s", "-o", os.devnull, "-w", "%{http_code}", "--max-time", str(timeout),
                            *(["-K", cfg] if cfg else []), *args], capture_output=True, text=True)
        return r.stdout.strip()
    finally:
        if cfg:
            os.unlink(cfg)


def find_ip():
    with urllib.request.urlopen(f"https://dns.google/resolve?name={HOST}&type=A", timeout=20) as r:
        ips = [a["data"] for a in json.load(r).get("Answer", []) if a.get("type") == 1]
    for ip in ips:
        code = curl(["--resolve", f"{HOST}:443:{ip}", f"https://{HOST}/"], timeout=10)
        print(f"  {ip}: {code}")
        if code == "403":
            return ip
    sys.exit("нет доступного адреса S3 среди " + ", ".join(ips or ["(DoH ничего не вернул)"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=None, help="ветка (по умолчанию текущая)")
    ap.add_argument("--ip", default=None, help="адрес S3 (по умолчанию — первый живой из DoH)")
    a = ap.parse_args()
    root = git("rev-parse", "--show-toplevel")
    os.chdir(root)
    ref = a.ref or git("rev-parse", "--abbrev-ref", "HEAD")
    url = git("remote", "get-url", "origin")
    slug = url.split("github.com")[-1].lstrip(":/").removesuffix(".git")

    objs = {}
    for line in git("lfs", "push", "--dry-run", "origin", ref).splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "push":
            oid = parts[1]
            p = os.path.join(root, ".git", "lfs", "objects", oid[:2], oid[2:4], oid)
            objs[oid] = (p, os.path.getsize(p))
    print(f"{slug} {ref}: объектов к выгрузке {len(objs)}")
    if not objs:
        return 0

    ip = a.ip or find_ip()
    print(f"S3 через {ip}")
    cred = dict(l.split("=", 1) for l in git("credential", "fill", inp="protocol=https\nhost=github.com\n\n").splitlines() if "=" in l)
    auth = "Basic " + base64.b64encode(f"{cred['username']}:{cred['password']}".encode()).decode()
    lfs_json = {"Accept": "application/vnd.git-lfs+json", "Content-Type": "application/vnd.git-lfs+json"}
    req = urllib.request.Request(
        f"https://github.com/{slug}.git/info/lfs/objects/batch", method="POST",
        data=json.dumps({"operation": "upload", "transfers": ["basic"],
                         "objects": [{"oid": o, "size": s} for o, (_, s) in objs.items()]}).encode(),
        headers={**lfs_json, "Authorization": auth})
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.load(r)

    done = skipped = failed = 0
    for o in resp["objects"]:
        acts = o.get("actions") or {}
        if "error" in o:
            print("ошибка", o["oid"][:10], o["error"])
            failed += 1
            continue
        if "upload" not in acts:
            skipped += 1        # уже на сервере
            continue
        up = acts["upload"]
        code = curl(["--resolve", f"{HOST}:443:{ip}", "-X", "PUT", "--data-binary", "@" + objs[o["oid"]][0], up["href"]],
                    up.get("header", {}))
        if not code.startswith("2"):
            print("PUT не прошёл", o["oid"][:10], code)
            failed += 1
            continue
        if "verify" in acts:
            v = acts["verify"]
            vr = urllib.request.Request(v["href"], method="POST", headers={**v.get("header", {}), **lfs_json},
                                        data=json.dumps({"oid": o["oid"], "size": o["size"]}).encode())
            urllib.request.urlopen(vr, timeout=60).close()
        done += 1
    print(f"выгружено {done}, уже было {skipped}, не прошло {failed}")
    if not failed:
        print("теперь обычный git push")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

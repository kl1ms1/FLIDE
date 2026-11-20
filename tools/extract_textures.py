#!/usr/bin/env python3
"""FLIDE: выгрузить ВСЕ текстуры прямо из файлов игры (не дожидаясь, пока их загрузит меню).

    python3 tools/extract_textures.py <in.ipa> <out_dir> [фильтр]

Имя файла = имя текстуры в игре, поэтому после правки папку можно сразу
импортировать в FLIDE как пак — замены подставятся сами.
Папки по разделам игры: ui/, scenes/, cards/ … (FLIDE их не учитывает).
"""
import os
import sys
import tempfile
import zipfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import UnityPy

SKIP = ("sdf", "font", "lightmap", "reflection")


def category(rel: str) -> str:
    p = rel.lower()
    for key, cat in (("/ui/uiatlas", "ui_atlas"), ("/ui/", "ui"), ("scenes", "tables"), ("card", "cards"),
                     ("emoji", "emoji"), ("avatar", "avatars"), ("effect", "effects"), ("spine", "spine")):
        if key in p:
            return cat
    return "other"


def work(args):
    path, rel, out, flt = args
    done = []
    try:
        env = UnityPy.load(path)
        for obj in env.objects:
            if obj.type.name != "Texture2D":
                continue
            tex = obj.read()
            name = tex.m_Name or ""
            if not name or any(s in name.lower() for s in SKIP):
                continue
            if flt and flt not in name.lower() and flt not in rel.lower():
                continue
            if min(tex.m_Width, tex.m_Height) < 16:
                continue
            safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in name)
            d = Path(out) / category(rel)
            d.mkdir(parents=True, exist_ok=True)
            dst = d / f"{safe}.png"
            if dst.exists():  # одинаковые имена — оставляем самую большую
                continue
            try:
                tex.image.save(dst)
                done.append(safe)
            except Exception:
                pass
    except Exception:
        pass
    return done


def main() -> None:
    ipa, out = Path(sys.argv[1]), Path(sys.argv[2])
    flt = sys.argv[3].lower() if len(sys.argv) > 3 and sys.argv[3] else ""
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa) as z:
            for n in z.namelist():
                if "/Data/" in n and (n.endswith(".assetbundle") or n.endswith(".assets") or "/Data/Resources/" in n):
                    z.extract(n, tmp)
        files = []
        for d, _, fs in os.walk(tmp):
            for f in fs:
                p = os.path.join(d, f)
                files.append((p, p.split("/Data/", 1)[-1], str(out), flt))
        print(f"файлов: {len(files)}", flush=True)
        total = 0
        with ProcessPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
            futs = [ex.submit(work, a) for a in files]
            for i, f in enumerate(as_completed(futs), 1):
                total += len(f.result())
                if i % 500 == 0:
                    print(f"{i}/{len(files)} … текстур: {total}", flush=True)
    print(f"готово: {total} текстур в {out}")


if __name__ == "__main__":
    main()

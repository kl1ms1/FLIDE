#!/usr/bin/env python3
"""FLIDE HD-пак: прогоняет каждую текстуру через Real-ESRGAN и возвращает
к исходному размеру (LANCZOS). Размер не меняется — спрайты в атласах не
съезжают, но картинка становится чище: меньше мыла и артефактов сжатия.

    python3 tools/hd_pack.py <src_dir> <out_dir> <esr_dir> <model>
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

SKIP = ("sdf", "font")  # шрифтовые атласы не трогаем


def main() -> None:
    src, out, esr, model = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
    out.mkdir(parents=True, exist_ok=True)
    binary = esr / "realesrgan-ncnn-vulkan"
    scale = "2" if model == "realesr-animevideov3" else "4"
    files = sorted(p for p in src.rglob("*") if p.suffix.lower() == ".png")
    done = skipped = failed = 0
    for i, f in enumerate(files, 1):
        name = f.name
        if any(s in name.lower() for s in SKIP):
            skipped += 1
            continue
        with Image.open(f) as im:
            size = im.size
        if min(size) < 16:
            skipped += 1
            continue
        with tempfile.TemporaryDirectory() as tmp:
            up = Path(tmp) / "up.png"
            cmd = [str(binary), "-i", str(f), "-o", str(up), "-n", model, "-s", scale, "-m", str(esr / "models")]
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0 or not up.exists():
                failed += 1
                print(f"[{i}/{len(files)}] FAIL {name}: {r.stderr.strip()[-200:]}")
                continue
            with Image.open(up) as big:
                big.convert("RGBA").resize(size, Image.LANCZOS).save(out / name, optimize=True)
        done += 1
        print(f"[{i}/{len(files)}] ok {name} {size[0]}x{size[1]}")
    print(f"готово: {done}, пропущено: {skipped}, ошибок: {failed}")


if __name__ == "__main__":
    main()

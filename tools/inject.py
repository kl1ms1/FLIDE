#!/usr/bin/env python3
"""FLIDE injector: встраивает .dylib в .ipa без Mac.

    python3 tools/inject.py <in.ipa> <out.ipa> <tweak.dylib> [ещё .dylib ...]

Кладёт дилибы в Payload/<App>.app/Frameworks/ и добавляет LC_LOAD_DYLIB
в главный бинарник. Подпись не нужна — Sideloadly/AltStore переподпишут.
"""
import plistlib
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import lief


def main() -> None:
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    src, dst, dylibs = Path(sys.argv[1]), Path(sys.argv[2]), [Path(p) for p in sys.argv[3:]]

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        with zipfile.ZipFile(src) as z:
            z.extractall(tmp)

        apps = list((tmp / "Payload").glob("*.app"))
        if len(apps) != 1:
            sys.exit(f"ожидался один .app в Payload, найдено: {apps}")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        exe = app / info["CFBundleExecutable"]
        print(f"app: {info['CFBundleIdentifier']} {info.get('CFBundleShortVersionString')}")

        fw = app / "Frameworks"
        fw.mkdir(exist_ok=True)

        fat = lief.MachO.parse(str(exe))
        if fat is None or fat.size != 1:
            sys.exit("ожидался тонкий arm64 бинарник")
        binary = fat.at(0)
        existing = {lib.name for lib in binary.libraries}

        for d in dylibs:
            shutil.copy2(d, fw / d.name)
            load_path = f"@executable_path/Frameworks/{d.name}"
            if load_path in existing:
                print(f"уже есть: {load_path}")
                continue
            binary.add_library(load_path)
            print(f"+ {load_path}")

        binary.write(str(exe))
        exe.chmod(0o755)

        # проверка
        check = lief.MachO.parse(str(exe)).at(0)
        names = {lib.name for lib in check.libraries}
        for d in dylibs:
            assert f"@executable_path/Frameworks/{d.name}" in names, d.name

        dst.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for f in sorted(tmp.rglob("*")):
                if f.is_file() or f.is_symlink():
                    z.write(f, f.relative_to(tmp))
        print(f"готово: {dst} ({dst.stat().st_size // (1024 * 1024)} МБ)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Assemble the single-file KoeDL.bat from the sources in src/.

Every part listed in build/manifest.json is literal text: the parts are joined
with CRLF and written as UTF-8 without BOM, exactly like the hand-maintained
.bat this replaces. Nothing is parsed or reformatted, so the output is
reproducible byte for byte.

Markers allowed inside a part (or inside an included file):

    @@VERSION@@         version taken from build/manifest.json
    @@INCLUDE:path@@    text of a file (one trailing newline trimmed)
    @@INCLUDE_DIR:dir@@ text of every *.css/*.js in dir, sorted by name
    @@B64:path@@        base64 of a binary file
    @@I18N:dir@@        compact JSON of dir/pt.json and dir/en.json

Usage:
    python3 build/build.py              # rewrite KoeDL.bat, Media-Downloader.bat and koedl.sh
    python3 build/build.py --check      # build in memory, fail if the files drifted
    python3 build/build.py --out dist   # also write fresh copies to dist/
    python3 build/build.py --version    # print the version from the manifest
"""

import base64
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "build", "manifest.json")

TOKEN = re.compile(r"@@(B64|INCLUDE_DIR|INCLUDE|I18N|VERSION):?([^@]*)@@")
MAX_DEPTH = 8


def abs_path(rel):
    path = os.path.normpath(os.path.join(ROOT, rel))
    if path != ROOT and not path.startswith(ROOT + os.sep):
        raise SystemExit("path outside the project: %s" % rel)
    return path


def read_text(rel):
    """Read a source file as UTF-8 text with LF endings and no trailing newline."""
    with open(abs_path(rel), "rb") as handle:
        data = handle.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    text = data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    return text[:-1] if text.endswith("\n") else text


def read_binary(rel):
    with open(abs_path(rel), "rb") as handle:
        return handle.read()


def read_dir(rel):
    base = abs_path(rel)
    names = sorted(
        name
        for name in os.listdir(base)
        if name.endswith((".css", ".js")) and os.path.isfile(os.path.join(base, name))
    )
    if not names:
        raise SystemExit("no .css/.js files in %s" % rel)
    return "\n".join(read_text(os.path.join(rel, name)) for name in names)


def read_i18n(rel):
    table = {}
    for lang in ("pt", "en"):
        with open(abs_path(os.path.join(rel, lang + ".json")), "rb") as handle:
            table[lang] = json.loads(handle.read().decode("utf-8"))
    return json.dumps(table, ensure_ascii=False)


def expand(text, version, depth=0, origin=""):
    if depth > MAX_DEPTH:
        raise SystemExit("include nesting too deep, starting at %s" % origin)

    def replace(match):
        kind, arg = match.group(1), match.group(2).strip()
        if kind == "VERSION":
            return version
        if kind == "B64":
            return base64.b64encode(read_binary(arg)).decode("ascii")
        if kind == "INCLUDE":
            return expand(read_text(arg), version, depth + 1, arg)
        if kind == "INCLUDE_DIR":
            return expand(read_dir(arg), version, depth + 1, arg)
        if kind == "I18N":
            return read_i18n(arg)
        raise SystemExit("unknown marker @@%s@@ in %s" % (kind, origin or "source"))

    return TOKEN.sub(replace, text)


def payload(manifest):
    """The PowerShell program itself, LF endings (shared by the .bat and the .sh)."""
    version = str(manifest["version"])
    return "\n".join(
        expand(read_text(part), version, origin=part) for part in manifest["parts"]
    )


def assembly(manifest):
    return (payload(manifest).replace("\n", "\r\n") + "\r\n").encode("utf-8")


def assembly_linux(manifest):
    """Bash launcher + the PowerShell program, so the .sh is self-contained like the .bat.

    The Windows launcher (boot.cmd) is dropped: the .sh only needs the part from
    the ###PS### marker on.
    """
    linux = manifest["linux"]
    version = str(manifest["version"])
    body = payload(manifest)
    marker = body.find("###" + "PS###")
    if marker >= 0:
        body = body[marker:]
    head = expand(read_text(linux["launcher"]), version, origin=linux["launcher"])
    return (head + "\n" + body + "\n__KOEDL_PAYLOAD_END__\n").encode("utf-8")


def main(argv):
    with open(MANIFEST, "rb") as handle:
        manifest = json.loads(handle.read().decode("utf-8"))

    if "--version" in argv:
        print(manifest["version"])
        return 0

    data = assembly(manifest)
    shdata = assembly_linux(manifest)
    outputs = manifest["outputs"]
    targets = [outputs["main"], outputs["legacy"]]
    built = [(name, data) for name in targets] + [(manifest["linux"]["output"], shdata)]

    if "--check" in argv:
        status = 0
        for name, blob in built:
            path = abs_path(name)
            current = read_binary(name) if os.path.exists(path) else b""
            if current == blob:
                print("ok       %s" % name)
            else:
                print("drifted  %s" % name)
                status = 1
            print("sha256   %s  (%d bytes)" % (hashlib.sha256(blob).hexdigest(), len(blob)))
        return status

    for name, blob in built:
        with open(abs_path(name), "wb") as handle:
            handle.write(blob)
        print("wrote    %s" % name)

    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
        os.makedirs(abs_path(out), exist_ok=True)
        for name, blob in built:
            with open(abs_path(os.path.join(out, name)), "wb") as handle:
                handle.write(blob)
        print("wrote    %s/" % out)

    for name, blob in built:
        print("sha256   %s  (%d bytes)  %s" % (hashlib.sha256(blob).hexdigest(), len(blob), name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

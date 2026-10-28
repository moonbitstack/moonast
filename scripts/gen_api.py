#!/usr/bin/env python3
"""Builds docs/api.html from each package's pkg.generated.mbti and the /// comments
in the package's sources. Deterministic: the same inputs give the same bytes."""

from __future__ import annotations

import glob
import html
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "docs", "api.html")

PACKAGES = ["quote", "attr", "gen", "cli"]

ABOUT = {
    "quote": "Templates: real MoonBit with <code>$holes</code>. A template is parsed with "
             "its holes standing as placeholders, each fill is put where its placeholder "
             "stands, and the result is printed by the official formatter.",
    "attr": "Annotations as typed arguments. Find <code>#lib.name(...)</code> on a "
            "declaration and bind its arguments against a spec; every refusal carries "
            "the position of the annotation.",
    "gen": "Declarations read from source into plain views, the <code>Generator</code> "
           "trait, and <code>render</code>, which gives the file a generator writes. No "
           "file access here.",
    "cli": "The command line of a generator binary: it reads the inputs, has "
           "<code>moonast/gen</code> render them, and writes the output or reports that "
           "it is stale.",
}

TITLES = {
    "quote": "quote",
    "attr": "attr",
    "gen": "gen",
    "cli": "cli",
}


# --------------------------------------------------------------- mbti parsing

class Item:
    def __init__(self, kind, name, sig, fields=None, variants=None, methods=None, derive=""):
        self.kind = kind          # value | struct | enum | error | trait
        self.name = name
        self.sig = sig
        self.fields = fields or []
        self.variants = variants or []
        self.methods = methods or []
        self.derive = derive


def strip_derive(line):
    m = re.search(r"\bderive\((.*)\)\s*$", line)
    if m:
        return " derive(" + m.group(1) + ")", m.group(1)
    return "", ""


def parse_mbti(text):
    section = None
    blocks = []
    plain = []          # (name, signature) for every `pub fn`
    current = None

    for raw in text.split("\n"):
        line = raw.rstrip()
        if not line:
            continue

        if line.startswith("//"):
            head = line[2:].strip()
            if head in ("Values", "Errors", "Types and methods", "Traits", "Type aliases"):
                section = head
            continue

        if line.startswith("pub impl ") or line.startswith("impl "):
            continue

        m = re.match(r"^pub(\((?:all|open)\))? (async )?fn ([A-Za-z_][\w:]*)\(", line)
        if m:
            plain.append((m.group(3), line.rstrip(" {")))
            continue

        m = re.match(r"^pub(\((?:all|open)\))? (struct|enum|suberror|trait) ([A-Za-z_]\w*)", line)
        if m:
            kind, name = m.group(2), m.group(3)
            tail, derived = strip_derive(line)
            base = line[: len(line) - len(tail)] if tail else line
            block = Item(
                {"struct": "struct", "enum": "enum", "suberror": "error", "trait": "trait"}[kind],
                name,
                base.rstrip(),
                derive=derived,
            )
            blocks.append(block)
            current = block if base.rstrip().endswith("{") else None
            continue

        if current is not None:
            if line.strip().startswith("}"):
                current = None
                continue
            body = line.strip()
            if body.startswith("//"):
                continue
            if current.kind == "trait":
                m = re.match(r"^(async )?fn ([A-Za-z_]\w*)\(", body)
                if m:
                    current.methods.append(
                        Item("value", current.name + "::" + m.group(2), body)
                    )
                continue
            if "(" in body and body.endswith(")"):
                current.variants.append(body.rstrip(","))
            elif body:
                current.fields.append(body)
            continue

    by_name = {b.name: b for b in blocks}
    values = []
    for name, sig in plain:
        if "::" in name:
            owner = name.split("::", 1)[0]
            if owner in by_name:
                by_name[owner].methods.append(Item("value", name, sig))
                continue
        values.append(Item("value", name, sig))

    for b in blocks:
        b.methods.sort(key=lambda m: m.name)

    types = [b for b in blocks if b.kind in ("struct", "enum")]
    traits = [b for b in blocks if b.kind == "trait"]
    errors = [b for b in blocks if b.kind == "error"]
    return values, types, errors, traits


# ------------------------------------------------------------- doc extraction

DECL = re.compile(
    r"^\s*(?:pub(?:\(all\)|\(open\))?\s+)?(?:async\s+)?"
    r"(fn|struct|enum|suberror|trait|type|extend|impl)\s+([A-Za-z_][\w:]*)"
)
VARIANT = re.compile(r"^\s{2,}([A-Za-z_]\w*)\s*(\(|:|$)")


def docs_for(pkg_dir):
    """Maps every documented name to the lines of its /// comment."""
    out = {}
    for path in sorted(glob.glob(os.path.join(pkg_dir, "*.mbt"))):
        lines = io.open(path, encoding="utf-8").read().split("\n")
        buf = []
        trait = None
        for line in lines:
            s = line.strip()
            if s == "///|":
                buf = []
                continue
            if s.startswith("///"):
                buf.append(s[3:].lstrip() if s != "///" else "")
                continue

            m = DECL.match(line)
            if m:
                kind, name = m.group(1), m.group(2)
                if buf and kind != "impl":
                    if kind == "trait":
                        trait = name
                        out.setdefault(name, list(buf))
                    elif trait is not None and kind == "fn" and "::" not in name:
                        out.setdefault(trait + "::" + name, list(buf))
                    else:
                        out.setdefault(name, list(buf))
                if kind == "trait":
                    trait = name
            if s == "}":
                trait = None
            buf = []

        # variants of enums and suberrors
        text_lines = lines
        for i, raw in enumerate(text_lines):
            if not raw.strip().startswith("///"):
                continue
            j = i
            while j >= 0 and (text_lines[j].strip().startswith("///") or text_lines[j].strip() == "///|"):
                j -= 1
            k = i + 1
            while k < len(text_lines) and (
                text_lines[k].strip().startswith("///") or text_lines[k].strip() == "///|"
            ):
                k += 1
            block = [
                (ln.strip()[3:].lstrip() if ln.strip() != "///" else "")
                for ln in text_lines[j + 1 : i + 1]
            ]
            if k < len(text_lines):
                m = VARIANT.match(text_lines[k])
                owner = None
                for q in range(j, -1, -1):
                    dm = DECL.match(text_lines[q])
                    if dm and dm.group(1) in ("enum", "suberror"):
                        owner = dm.group(2)
                        break
                if m and owner:
                    out[owner + "::" + m.group(1)] = block
    return out


# ------------------------------------------------------------------ rendering

FALLBACK = {
    "output": "Writes the value to a logger, as <code>Show</code> defines it.",
    "to_string": "The value as a string, as <code>Show</code> defines it.",
    "to_repr": "The value as a <code>Repr</code>, as <code>Debug</code> defines it.",
    "equal": "Whether two values are equal, as <code>Eq</code> defines it.",
    "not_equal": "Whether two values differ, as <code>Eq</code> defines it.",
}


def tidy(code):
    """Puts a doctest back on one line where `moon fmt` split it to fit."""
    code = re.sub(
        r"content=\(\s*\n\s*#\|(.*?)\s*\n\s*\)",
        lambda m: 'content="' + m.group(1).strip() + '"',
        code,
        flags=re.S,
    )
    lines = code.split("\n")
    out = []
    i = 0
    while i < len(lines):
        if lines[i].rstrip().endswith("("):
            j = i + 1
            parts = [lines[i].rstrip()]
            ok = False
            while j < len(lines):
                t = lines[j].strip()
                if t in (")", "),"):
                    parts.append(t)
                    ok = True
                    j += 1
                    break
                if not lines[j].startswith("  "):
                    break
                parts.append(t)
                j += 1
            if ok:
                args = parts[1:]
                closing = args.pop() if args and args[-1] in (")", "),") else ""
                joined = parts[0] + (" " if args else "") + " ".join(args) + closing
                if len(joined) <= 92 and "\n" not in joined:
                    out.append(joined)
                    i = j
                    continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def inline(text):
    out = html.escape(text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", out)


def render_doc(lines):
    """A small markdown subset: fenced code, paragraphs, inline code."""
    if not lines:
        return ""
    blocks = []
    buf = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("```"):
            if buf:
                blocks.append(("p", buf))
                buf = []
            lang = ln[3:].strip()
            body = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(lines[i])
                i += 1
            i += 1
            blocks.append(("code", (lang, body)))
            continue
        if not ln.strip():
            if buf:
                blocks.append(("p", buf))
                buf = []
            i += 1
            continue
        buf.append(ln)
        i += 1
    if buf:
        blocks.append(("p", buf))

    out = []
    for kind, payload in blocks:
        if kind == "p":
            out.append("<p>" + inline(" ".join(payload)) + "</p>")
        else:
            lang, body = payload
            code = "\n".join(body)
            head = lang.split(" ")[0] if lang else ""
            if head in ("mbt", "moonbit"):
                # A `mbt check` block is a test; show the example, not the harness.
                code = re.sub(r"^test \{\n", "", code)
                code = re.sub(r"\n\}\s*$", "", code)
                body = [ln for ln in code.split("\n") if ln.strip()]
                cut = min((len(ln) - len(ln.lstrip(" ")) for ln in body), default=0)
                code = "\n".join(ln[cut:] if ln.strip() else ln for ln in code.split("\n"))
                code = tidy(code)
                out.append(
                    '<pre data-lang="moonbit"><code>' + html.escape(code.strip("\n")) + "</code></pre>"
                )
            else:
                out.append("<pre data-raw=\"1\"><code>" + html.escape(code) + "</code></pre>")
    return "\n".join(out)


def esc(text):
    return html.escape(text)


def anchor(name):
    return name.replace("::", ".").replace(" ", "-")


def entry_html(pkg, item, docs, level=3):
    key = item.name
    doc_lines = docs.get(key) or docs.get(key.split("::")[-1]) or []
    if not doc_lines and "::" in key:
        doc_lines = [FALLBACK.get(key.split("::")[-1], "")]
    sig = esc(item.sig)
    cls = {
        "value": "kind-value",
        "struct": "kind-type",
        "enum": "kind-type",
        "error": "kind-error",
        "trait": "kind-type",
    }[item.kind]

    parts = ['<div class="entry %s" id="%s.%s">' % (cls, pkg, anchor(item.name))]
    parts.append('<div class="sig">%s <a class="anchor" href="#%s.%s">#</a></div>' % (sig, pkg, anchor(item.name)))

    if item.derive:
        parts.append('<div class="doc"><p>Derives %s.</p></div>' % esc(item.derive))

    doc = render_doc(doc_lines)
    if doc:
        parts.append('<div class="doc">%s</div>' % doc)

    if item.fields:
        parts.append("<ul class=\"params\">")
        for f in item.fields:
            if f.startswith("//"):
                continue
            if ":" in f:
                n, _, t = f.partition(":")
                parts.append(
                    '<li><span class="pname">%s</span> : %s</li>' % (esc(n.strip()), esc(t.strip()))
                )
            else:
                parts.append('<li><span class="pname">%s</span></li>' % esc(f))
        parts.append("</ul>")

    if item.variants:
        parts.append('<ul class="params">')
        for v in item.variants:
            m = re.match(r"^([A-Za-z_]\w*)\s*(\((.*)\))?$", v.strip())
            if not m:
                parts.append('<li><span class="pname">%s</span></li>' % esc(v.strip()))
                continue
            vname = m.group(1)
            args = m.group(3) or ""
            sub = docs.get(item.name + "::" + vname) or []
            extra = " — " + inline(" ".join(sub)) if sub else ""
            shown = vname + ("(" + args + ")" if args else "")
            parts.append('<li><span class="pname">%s</span>%s</li>' % (esc(shown), extra))
        parts.append("</ul>")

    if item.methods:
        for mth in sorted(item.methods, key=lambda m: m.name):
            mdoc = docs.get(mth.name) or docs.get(mth.name.split("::")[-1]) or []
            if not mdoc:
                tail = mth.name.split("::")[-1]
                if tail in FALLBACK:
                    mdoc = [FALLBACK[tail]]
            parts.append(
                '<div class="entry kind-value" id="%s.%s" style="border-top:0;padding-top:8px">'
                % (pkg, anchor(mth.name))
            )
            parts.append(
                '<div class="sig">%s <a class="anchor" href="#%s.%s">#</a></div>'
                % (esc(mth.sig), pkg, anchor(mth.name))
            )
            md = render_doc(mdoc)
            if md:
                parts.append('<div class="doc">%s</div>' % md)
            parts.append("</div>")

    parts.append("</div>")
    return "\n".join(parts)


def group_html(pkg, title, items, docs):
    if not items:
        return ""
    out = ['<h3 id="%s-%s">%s</h3>' % (pkg, title.lower().replace(" ", "-"), title)]
    for item in sorted(items, key=lambda i: i.name):
        out.append(entry_html(pkg, item, docs))
    return "\n".join(out)


def build():
    nav = []
    body = []

    for pkg in PACKAGES:
        mbti_path = os.path.join(SRC, pkg, "pkg.generated.mbti")
        if not os.path.exists(mbti_path):
            print("missing", mbti_path, file=sys.stderr)
            continue
        text = io.open(mbti_path, encoding="utf-8").read()
        values, types, errors, traits = parse_mbti(text)
        docs = docs_for(os.path.join(SRC, pkg))

        nav.append('<div class="group"><h4>%s</h4>' % esc(TITLES[pkg]))
        for v in sorted(values, key=lambda i: i.name):
            nav.append('<a class="sub" href="#%s.%s">%s</a>' % (pkg, anchor(v.name), esc(v.name)))
        for t in sorted(types, key=lambda i: i.name):
            nav.append('<a class="sub" href="#%s.%s">%s</a>' % (pkg, anchor(t.name), esc(t.name)))
        for t in sorted(traits, key=lambda i: i.name):
            nav.append('<a class="sub" href="#%s.%s">%s</a>' % (pkg, anchor(t.name), esc(t.name)))
        for e in sorted(errors, key=lambda i: i.name):
            nav.append('<a class="sub" href="#%s.%s">%s</a>' % (pkg, anchor(e.name), esc(e.name)))
        nav.append("</div>")

        body.append('<section class="pkg" id="pkg-%s">' % pkg)
        body.append('<h2>%s<span class="path">moonbitstack/moonast/%s</span></h2>' % (esc(TITLES[pkg]), pkg))
        body.append('<p class="about">%s</p>' % ABOUT[pkg])
        body.append(group_html(pkg, "Values", values, docs))
        body.append(group_html(pkg, "Types", types, docs))
        body.append(group_html(pkg, "Traits", traits, docs))
        body.append(group_html(pkg, "Errors", errors, docs))
        body.append("</section>")

    return "\n".join(nav), "\n".join(body)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API reference — moonast</title>
<meta name="description" content="Every public type, function, method, trait and error of moonast, grouped by package.">
<link rel="icon" href="data:image/svg+xml,%%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%%3E%%3Crect width='32' height='32' rx='7' fill='%%23272121'/%%3E%%3Ctext x='16' y='24' font-family='monospace' font-size='21' fill='%%23e16428' text-anchor='middle'%%3E%%24%%3C/text%%3E%%3C/svg%%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,800&family=Instrument+Sans:wght@400;500;600&family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="site.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>

<header class="top">
  <div class="wrap">
    <a class="mark" href="index.html"><span class="glyph">$<b>#</b></span>moonast</a>
    <nav class="nav">
      <a href="index.html">Home</a>
      <a href="guide.html">Guide</a>
      <a href="api.html" aria-current="page">API</a>
      <a href="play.html">Playground</a>
      <a class="icon" data-theme-toggle href="#" title="Switch theme" aria-label="Switch theme">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4.2"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6L17 7M7 17l-1.4 1.4"/></svg>
      </a>
      <a class="icon" href="https://github.com/moonbitstack/moonast" title="moonast on GitHub" aria-label="moonast on GitHub">
        <svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.42 7.42 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A7.995 7.995 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
      </a>
    </nav>
  </div>
</header>

<div class="wrap">
  <div class="doc">
    <aside class="side">
__NAV__
    </aside>

    <div class="prose" id="main">
      <section style="margin-bottom:34px">
        <h2 style="border-bottom:0;padding-bottom:0">API reference</h2>
        <p>Every public type, function, method, trait and error, grouped by package and
          listed alphabetically within each group. Import one package at a time:
          <code>moonbitstack/moonast/quote</code>, <code>/attr</code>, <code>/gen</code>,
          <code>/cli</code>.</p>
      </section>
__BODY__
    </div>
  </div>
</div>

<footer class="site">
  <div class="wrap">
    <p>moonast — Apache-2.0</p>
    <div class="r">
      <a href="index.html">Home</a>
      <a href="guide.html">Guide</a>
      <a href="api.html">API</a>
      <a href="play.html">Playground</a>
      <a class="icon" href="https://github.com/moonbitstack/moonast" title="moonast on GitHub" aria-label="moonast on GitHub">
        <svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.42 7.42 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A7.995 7.995 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
      </a>
    </div>
  </div>
</footer>

<script src="site.js"></script>
</body>
</html>
"""


def main():
    nav, body = build()
    out = TEMPLATE.replace("__NAV__", nav).replace("__BODY__", body)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(out)
    print("wrote", OUT, len(out), "bytes")


if __name__ == "__main__":
    main()

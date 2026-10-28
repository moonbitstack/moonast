/* moonast site: syntax painting, the theme, the foil that follows the pointer,
   and the loader for the compiled engine.

   The painting is deliberately small: a token scanner for MoonBit as this
   library's pages write it, and an alignment pass for trailing comments. */

(() => {
  "use strict";

  const KEYWORDS = new Set(
    ("fn let mut const struct enum type trait impl with derive pub priv pub(all) pub(open) " +
      "extern async match guard raise try catch else if for while loop continue break return " +
      "where test inspect as is and or not abort ignore true false self None Some").split(" ")
  );

  /* ------------------------------------------------------------ escaping */

  const esc = (s) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  /* A grapheme that is not ASCII is wrapped so it occupies a whole number of
     character cells; otherwise padding a trailing comment with spaces drifts. */
  const WIDE =
    /[\u1100-\u115F\u2E80-\uA4CF\uA960-\uA97F\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6\u{1F000}-\u{1FAFF}\u{20000}-\u{3FFFF}]/u;

  function wrap(text) {
    let out = "";
    for (const ch of text) {
      const cp = ch.codePointAt(0);
      if (cp < 0x80) out += ch;
      else out += '<span class="' + (WIDE.test(ch) ? "w2" : "w1") + '">' + esc(ch) + "</span>";
    }
    return out;
  }

  const width = (text) => {
    let n = 0;
    for (const ch of text) n += WIDE.test(ch) ? 2 : 1;
    return n;
  };

  /* ----------------------------------------------------------- tokenizer */

  function paint(line) {
    let out = "";
    let i = 0;
    const n = line.length;
    while (i < n) {
      const c = line[i];
      const two = line.slice(i, i + 2);

      if (two === "//") {
        out += '<span class="tk-com">' + wrap(line.slice(i)) + "</span>";
        return out;
      }
      if (two === "#|") {
        out += '<span class="tk-str">' + wrap(line.slice(i)) + "</span>";
        return out;
      }
      if (c === '"') {
        let j = i + 1;
        while (j < n && line[j] !== '"') j += line[j] === "\\" ? 2 : 1;
        j = Math.min(j + 1, n);
        out += '<span class="tk-str">' + wrap(line.slice(i, j)) + "</span>";
        i = j;
        continue;
      }
      if (c === "#" && /[A-Za-z_]/.test(line[i + 1] || "")) {
        let j = i + 1;
        while (j < n && /[A-Za-z0-9_.]/.test(line[j])) j += 1;
        out += '<span class="tk-attr">' + esc(line.slice(i, j)) + "</span>";
        i = j;
        continue;
      }
      if (c === "$") {
        let j = i + 1;
        while (j < n && /[A-Za-z0-9_]/.test(line[j])) j += 1;
        if (j > i + 1) {
          if (j < n && line[j] === "*") j += 1;
          out += '<span class="tk-hole">' + esc(line.slice(i, j)) + "</span>";
          i = j;
          continue;
        }
        if (line[i + 1] === "$") {
          out += '<span class="tk-hole">$$</span>';
          i += 2;
          continue;
        }
      }
      if (/[A-Za-z_]/.test(c)) {
        let j = i;
        while (j < n && /[A-Za-z0-9_]/.test(line[j])) j += 1;
        const word = line.slice(i, j);
        const cls = KEYWORDS.has(word) ? "tk-key" : /^[A-Z]/.test(word) ? "tk-ty" : "";
        out += cls ? '<span class="' + cls + '">' + esc(word) + "</span>" : esc(word);
        i = j;
        continue;
      }
      if (/[0-9]/.test(c)) {
        let j = i;
        while (j < n && /[0-9_a-zA-Z]/.test(line[j])) j += 1;
        out += '<span class="tk-num">' + esc(line.slice(i, j)) + "</span>";
        i = j;
        continue;
      }
      if ("(){}[]<>,;:|?!&+-*/%=~.".includes(c)) {
        out += '<span class="tk-punct">' + esc(c) + "</span>";
        i += 1;
        continue;
      }
      out += wrap(c);
      i += 1;
    }
    return out;
  }

  /* -------------------------------------------------- comment alignment */

  function align(lines) {
    const parts = lines.map((ln) => {
      let inStr = false;
      for (let i = 0; i < ln.length; i++) {
        if (ln[i] === '"' && ln[i - 1] !== "\\") inStr = !inStr;
        else if (!inStr && ln[i] === "/" && ln[i + 1] === "/") {
          return { code: ln.slice(0, i), tail: ln.slice(i) };
        }
      }
      return { code: ln, tail: "" };
    });
    const col = parts.reduce(
      (m, p) => (p.tail ? Math.max(m, width(p.code.replace(/\s+$/, ""))) : m),
      0
    );
    return parts.map((p) => {
      if (!p.tail) return p.code;
      const bare = p.code.replace(/\s+$/, "");
      const pad = " ".repeat(Math.max(2, col - width(bare) + 2));
      return bare + pad + p.tail;
    });
  }

  function render(el) {
    const raw = el.textContent.replace(/\n+$/, "");
    if (!raw.trim()) return;
    const lines = align(raw.split("\n"));
    el.innerHTML = lines
      .map((ln) => {
        let at = -1;
        let inStr = false;
        for (let i = 0; i < ln.length; i++) {
          if (ln[i] === '"' && ln[i - 1] !== "\\") inStr = !inStr;
          else if (!inStr && ln[i] === "/" && ln[i + 1] === "/") { at = i; break; }
        }
        if (at === -1) return paint(ln);
        return paint(ln.slice(0, at)) + '<span class="tk-com">' + wrap(ln.slice(at)) + "</span>";
      })
      .join("\n");
  }

  function paintAll(root) {
    root
      .querySelectorAll("pre[data-lang='moonbit'] > code, pre.code[data-lang='moonbit'] > code")
      .forEach(render);
    root.querySelectorAll("pre:not([data-lang]) > code").forEach((c) => {
      const p = c.parentElement;
      if (p.dataset.raw !== "1") render(c);
    });
  }

  /* -------------------------------------------------------------- theme */

  const root = document.documentElement;
  const stored = localStorage.getItem("moonast-theme");
  if (stored === "light" || stored === "dark") root.dataset.theme = stored;

  const label = (btn) => {
    const dark = root.dataset.theme
      ? root.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    btn.setAttribute("aria-label", dark ? "Switch to light" : "Switch to dark");
    btn.setAttribute("title", dark ? "Switch to light" : "Switch to dark");
  };

  const toggle = (btn) => {
    const dark = root.dataset.theme
      ? root.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    root.dataset.theme = dark ? "light" : "dark";
    localStorage.setItem("moonast-theme", root.dataset.theme);
    label(btn);
  };

  /* ------------------------------------------------- the foil on a plate */

  function sheen() {
    document.querySelectorAll(".plate.lit").forEach((plate) => {
      plate.addEventListener("pointermove", (e) => {
        const r = plate.getBoundingClientRect();
        plate.style.setProperty("--mx", ((e.clientX - r.left) / r.width) * 100 + "%");
        plate.style.setProperty("--my", ((e.clientY - r.top) / r.height) * 100 + "%");
      });
    });
  }

  /* ------------------------------------------- mark the section in view */

  function sections() {
    const links = [...document.querySelectorAll(".side a[href^='#']")];
    if (!links.length) return;
    const map = new Map();
    links.forEach((a) => {
      const el = document.getElementById(a.getAttribute("href").slice(1));
      if (el) map.set(el, a);
    });
    if (!map.size || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          const a = map.get(e.target);
          if (!a) return;
          links.forEach((l) => l.classList.remove("on"));
          a.classList.add("on");
        });
      },
      { rootMargin: "-90px 0px -68% 0px" }
    );
    map.forEach((_, el) => io.observe(el));
  }

  /* ------------------------------------------------------ editor height */

  document.addEventListener("DOMContentLoaded", () => {
    paintAll(document);
    sheen();
    sections();
    document.querySelectorAll("[data-theme-toggle]").forEach((b) => {
      label(b);
      b.addEventListener("click", (e) => {
        e.preventDefault();
        toggle(b);
      });
    });
  });

  /* ----------------------------------------------- the compiled engine */

  const ENGINE = "play.js";
  let loading = null;

  function loadEngine() {
    if (window.moonast) return Promise.resolve(window.moonast);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = ENGINE;
      s.async = true;
      s.onload = () =>
        window.moonast ? resolve(window.moonast) : reject(new Error("engine did not register"));
      s.onerror = () => reject(new Error("could not load " + ENGINE));
      document.head.appendChild(s);
    });
    return loading;
  }

  window.moonastSite = { render, paintAll, loadEngine, esc, US: "\u001F", RS: "\u001E" };
})();

name = "moonbitstack/moonast"

version = "0.2.1"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonast"

license = "Apache-2.0"

keywords = [ "moonbit", "codegen", "ast", "macro", "derive", "attribute" ]

description = "Generate MoonBit code from annotated declarations: templates over the official syntax tree, typed attribute arguments, and the scaffolding a dev_build generator needs. Built on moonbitlang/parser; not a parser itself."

preferred_target = "wasm-gc"

import {
  "moonbitlang/parser@0.4.6",
  "moonbitlang/async@0.22.5",
}

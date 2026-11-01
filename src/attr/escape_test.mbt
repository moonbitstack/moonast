// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What `summary` reads as when the source writes `written` between the quotes.
fn summary_of(written : String) -> String? raise {
  let source = "#app.get(\"/\", summary=\"\{written}\")\nfn f() -> Unit { () }"
  let attr = @attr.find(attrs_of(source), "app.get").unwrap()
  get.bind(attr).str("summary")
}

///|
test "a string annotation reads as its author meant it" {
  let cases : Array[(String, String)] = [
    ("plain", "plain"),
    ("a\\\"b", "a\"b"),
    ("a\\\\b", "a\\b"),
    ("a\\nb", "a\nb"),
    ("a\\tb", "a\tb"),
    ("\\x41", "A"),
    ("\\o101", "A"),
    ("\\u0041", "A"),
    ("\\u{1F600}", "\u{1F600}"),
    ("^\\\\d+$", "^\\d+$"),
  ]
  for one in cases {
    let (written, meant) = one
    assert_eq(summary_of(written), Some(meant))
  }
}

///|
test "an escape that means nothing stays as written" {
  assert_eq(summary_of("\\q"), Some("\\q"))
}

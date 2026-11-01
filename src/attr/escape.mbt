// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The digits at `chars[from:to]` read in `radix`, `None` when any is not a digit
/// there or the range runs off the end.
fn digits(
  chars : Array[Char],
  from : Int32,
  to : Int32,
  radix : Int32,
) -> Int32? {
  if to > chars.length() || from >= to {
    return None
  }
  let mut out = 0
  for i in from..<to {
    let c = chars[i].to_int()
    let digit = if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
      c - 'a'.to_int() + 10
    } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
      c - 'A'.to_int() + 10
    } else {
      return None
    }
    if digit >= radix {
      return None
    }
    out = out * radix + digit
  }
  Some(out)
}

///|
/// A string as its author means it. The attribute parser hands back the source
/// text between the quotes, escapes and all, so `pattern="^\\d+$"` would otherwise
/// reach a generator with two backslashes. An escape that means nothing stays as
/// it was written.
fn decoded(text : String) -> String {
  guard text.contains("\\") else { return text }
  let chars = text.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '\\' || i + 1 == chars.length() {
      out.write_char(c)
      i = i + 1
      continue
    }
    let next = chars[i + 1]
    let (code, used) = match next {
      '\\' | '"' | '\'' => (Some(next.to_int()), 2)
      'n' => (Some(10), 2)
      'r' => (Some(13), 2)
      't' => (Some(9), 2)
      'b' => (Some(8), 2)
      'x' => (digits(chars, i + 2, i + 4, 16), 4)
      'o' => (digits(chars, i + 2, i + 5, 8), 5)
      'u' if i + 2 < chars.length() && chars[i + 2] == '{' => {
        let mut end = i + 3
        while end < chars.length() && chars[end] != '}' {
          end = end + 1
        }
        (digits(chars, i + 3, end, 16), end - i + 1)
      }
      'u' => (digits(chars, i + 2, i + 6, 16), 6)
      _ => (None, 1)
    }
    match code {
      Some(n) if n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) => {
        out.write_char(n.unsafe_to_char())
        i = i + used
      }
      _ => {
        out.write_char(c)
        i = i + 1
      }
    }
  }
  out.to_string()
}

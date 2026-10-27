///|
/// A `$name` or `$name*` in a template.
priv struct Hole {
  name : String
  many : Bool
}

///|
/// The identifier a hole stands as while the template is parsed. Its case follows
/// the hole's, because the grammar decides by case whether a position takes a
/// type or constructor (upper) or a value or binder (lower); a list hole always
/// stands where an expression does.
fn placeholder(hole : Hole) -> String {
  let upper = hole.name.get_char(0) is Some('A'..<='Z')
  if upper && !hole.many {
    "Moonast__" + hole.name
  } else {
    "moonast__" + hole.name
  }
}

///|
/// The template with every hole replaced by its placeholder, and the holes in the
/// order they first appear. `$$` is a literal `$`.
fn scan(source : StringView) -> (String, Array[Hole]) {
  let out = StringBuilder()
  let holes : Array[Hole] = []
  let chars = source.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '$' {
      out.write_char(c)
      i = i + 1
      continue
    }
    if i + 1 < chars.length() && chars[i + 1] == '$' {
      out.write_char('$')
      i = i + 2
      continue
    }
    let mut j = i + 1
    while j < chars.length() &&
          (
            chars[j] is ('a'..<='z' | 'A'..<='Z' | '_') ||
            (j > i + 1 && chars[j] is ('0'..<='9'))
          ) {
      j = j + 1
    }
    if j == i + 1 {
      out.write_char(c)
      i = i + 1
      continue
    }
    let name = String::from_array(chars[i + 1:j])
    let many = j < chars.length() && chars[j] == '*'
    let hole = { name, many, }
    if !holes.iter().any(h => h.name == name) {
      holes.push(hole)
    }
    out.write_string(placeholder(hole))
    i = if many { j + 1 } else { j }
  }
  (out.to_string(), holes)
}

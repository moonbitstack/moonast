///|
/// The full name of an annotation, `lib.name` for `#lib.name(...)`; `None` when
/// moonbitlang/parser could not read its payload.
pub fn name_of(attr : @attribute.Attribute) -> String? {
  match attr.parsed {
    Some(Ident(id)) | Some(Apply(id, _)) =>
      Some(
        match id.qual {
          Some(q) => q + "." + id.name
          None => id.name
        },
      )
    _ => None
  }
}

///|
/// The first annotation called `name`.
pub fn find(
  attrs : @list.List[@attribute.Attribute],
  name : StringView,
) -> @attribute.Attribute? {
  let name = name.to_owned()
  attrs.iter().find_first(a => name_of(a) is Some(n) && n == name)
}

///|
/// Every annotation called `name`, in source order.
pub fn all(
  attrs : @list.List[@attribute.Attribute],
  name : StringView,
) -> Array[@attribute.Attribute] {
  let name = name.to_owned()
  attrs.iter().filter(a => name_of(a) is Some(n) && n == name).collect()
}

///|
/// Every annotation whose name starts with `lib.`, in source order: a generator
/// for `#app.get`, `#app.post` and the rest asks once for `app`.
pub fn under(
  attrs : @list.List[@attribute.Attribute],
  lib : StringView,
) -> Array[@attribute.Attribute] {
  let prefix = lib.to_owned() + "."
  attrs
  .iter()
  .filter(a => name_of(a) is Some(n) && n.has_prefix(prefix))
  .collect()
}

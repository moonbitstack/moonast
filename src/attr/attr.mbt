///|
/// The full name of an annotation, `lib.name` for `#lib.name(...)`; `None` when
/// the parser could not read its payload.
///
/// ```mbt check
/// test {
///   let source = "#app.get(\"/users\", tag=\"users\")\nfn list_users() -> Unit {}"
///   let impls = @parser.parse_string(source).0
///   guard impls is @list.More(impl_, tail=@list.Empty) else {
///     abort("one declaration")
///   }
///   guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
///     abort("a function")
///   }
///   guard @attr.find(attrs, "app.get") is Some(a) else { abort("annotated") }
///   inspect(@attr.name_of(a).unwrap_or(""), content="app.get")
/// }
/// ```
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
///
/// ```mbt check
/// test {
///   let source = "#app.get(\"/users\", tag=\"users\")\nfn list_users() -> Unit {}"
///   let impls = @parser.parse_string(source).0
///   guard impls is @list.More(impl_, tail=@list.Empty) else {
///     abort("one declaration")
///   }
///   guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
///     abort("a function")
///   }
///   inspect(@attr.find(attrs, "app.get") is Some(_), content="true")
/// }
/// ```
pub fn find(
  attrs : @list.List[@attribute.Attribute],
  name : StringView,
) -> @attribute.Attribute? {
  let name = name.to_owned()
  attrs.iter().find_first(a => name_of(a) is Some(n) && n == name)
}

///|
/// Every annotation called `name`, in source order.
///
/// ```mbt check
/// test {
///   let source = "#app.get(\"/users\", tag=\"users\")\nfn list_users() -> Unit {}"
///   let impls = @parser.parse_string(source).0
///   guard impls is @list.More(impl_, tail=@list.Empty) else {
///     abort("one declaration")
///   }
///   guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
///     abort("a function")
///   }
///   inspect(@attr.all(attrs, "app.get").length(), content="1")
/// }
/// ```
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
///
/// ```mbt check
/// test {
///   let source = "#app.get(\"/users\", tag=\"users\")\nfn list_users() -> Unit {}"
///   let impls = @parser.parse_string(source).0
///   guard impls is @list.More(impl_, tail=@list.Empty) else {
///     abort("one declaration")
///   }
///   guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
///     abort("a function")
///   }
///   inspect(@attr.under(attrs, "app").length(), content="1")
/// }
/// ```
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

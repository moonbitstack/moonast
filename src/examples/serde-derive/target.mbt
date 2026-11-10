///|
/// What a derive needs to know about one type: its name, the parameters it is
/// generic over, its body, and which of the two implementations were asked for.
struct Target {
  name : String
  params : Array[String]
  public : Bool
  body : Body
  serialize : Bool
  deserialize : Bool
}

///|
/// The shapes the two implementations are written against.
enum Body {
  Unit
  Newtype
  Tuple(Int32)
  Record(Array[Entry])
  Variants(Array[Variant])
}

///|
/// A field of a record, as it is written on the wire and in the source.
struct Entry {
  ident : String
  name : String
  optional : Bool
  skip : Bool
}

///|
/// A variant of an enum, with what it carries.
struct Variant {
  ident : String
  name : String
  body : Body
}

///|
/// Why the derive stopped, as one sentence. An annotation that does not bind is
/// reported by `moonast/attr` and arrives here already naming the file, line and
/// column it stands at; the rules this derive enforces add their own place the
/// same way.
#derive(Debug)
pub(all) suberror Refused {
  Bad(msg~ : String)
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let text = match self {
    Bad(msg~) => msg
  }
  logger.write_string(text)
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// `#serde.derive(Serialize, Deserialize)`: a list of trait names written as bare
/// arguments, in the order they are listed.
fn derive_spec() -> @attr.Spec {
  @attr.Spec::new("serde.derive").many("trait", Ident, positional=true)
}

///|
/// `#serde.rename("max-retries")`: the name this entry has on the wire.
fn rename_spec() -> @attr.Spec {
  @attr.Spec::new("serde.rename").positional("name", Str)
}

///|
/// `#serde.skip`: written nowhere, and filled from `Default` on the way back.
fn skip_spec() -> @attr.Spec {
  @attr.Spec::new("serde.skip")
}

///|
/// Where a declaration stands: the file `moonast/gen` read it from, and the
/// position, `file:line:column`, a message about it points at.
struct Place {
  file : String
  at : String
}

///|
fn place_of(decl : @gen.Decl) -> Place {
  let start = decl.raw().loc().start
  let file = decl.file()
  { file, at: "\{file}:\{start.lnum}:\{start.column()}", }
}

///|
/// A refusal that names the place it is about.
fn refuse(place : Place, msg : String) -> Refused {
  Bad(msg="\{place.at}: \{msg}")
}

///|
/// Bind an annotation, handing `moonast/attr` the file so its message names the
/// file, line and column the annotation stands at. Nothing is added to it here:
/// the payload's place is its own, not the declaration's.
fn arguments(
  spec : @attr.Spec,
  annotation : @attribute.Attribute,
  place : Place,
) -> @attr.Args raise {
  spec.bind(annotation, file=place.file) catch {
    e => raise Bad(msg=e.to_string())
  }
}

///|
/// The names on a entry's annotations. Anything under `serde.` that cannot be
/// read is reported rather than passed over, and so is a name this derive does
/// not know.
fn member_attributes(
  attrs : @list.List[@attribute.Attribute],
  place : Place,
  ident : String,
) -> (String, Bool) raise {
  guard @attr.malformed(attrs, "serde").is_empty() else {
    raise refuse(place, "cannot make sense of an annotation on `\{ident}`")
  }
  let mut name = ident
  let mut skip = false
  for annotation in @attr.under(attrs, "serde") {
    let call = @attr.name_of(annotation).unwrap_or("")
    match call {
      "serde.rename" => {
        let args = arguments(rename_spec(), annotation, place)
        name = args.str("name").unwrap_or(ident)
      }
      "serde.skip" => {
        let _ = arguments(skip_spec(), annotation, place)
        skip = true
      }
      other =>
        raise refuse(place, "unknown annotation `#\{other}` on `\{ident}`")
    }
  }
  (name, skip)
}

///|
/// The members of a record, in source order, refusing two fields that would be
/// written under the same name.
fn members_of(fields : Array[@gen.Field], place : Place) -> Array[Entry] raise {
  let members = fields.map(field => {
    let (name, skip) = member_attributes(field.attrs, place, field.name)
    { ident: field.name, name, optional: field.optional, skip, }
  })
  for index, entry in members {
    guard !entry.skip else { continue }
    for earlier in 0..<index {
      let other = members[earlier]
      guard other.skip || other.name != entry.name else {
        raise refuse(
          place,
          "fields `\{other.ident}` and `\{entry.ident}` both serialize as `\{entry.name}`",
        )
      }
    }
  }
  members
}

///|
/// One variant, refusing the payload shapes that have no data model equivalent.
fn variant_of(case_ : @gen.Case, place : Place) -> Variant raise {
  let (name, skip) = member_attributes(case_.attrs, place, case_.name)
  guard !skip else {
    raise refuse(
      place,
      "`#serde.skip` is not supported on the variant `\{case_.name}`",
    )
  }
  let body = match case_.payload {
    Empty => Unit
    Tuple(arity~) => if arity == 1 { Newtype } else { Tuple(arity) }
    Record(fields~) => Record(members_of(fields, place))
    Cases(_) => raise refuse(place, "a variant cannot hold an enum")
  }
  { ident: case_.name, name, body, }
}

///|
/// The body of a type, `None` when it is not something a derive can write.
fn body_of(decl : @gen.Decl, place : Place) -> Body? raise {
  match decl.shape() {
    None => None
    Some(Empty) => Some(Unit)
    Some(Tuple(arity~)) => Some(if arity == 1 { Newtype } else { Tuple(arity) })
    Some(Record(fields~)) => Some(Record(members_of(fields, place)))
    Some(Cases(cases~)) => Some(Variants(cases.map(c => variant_of(c, place))))
  }
}

///|
/// The targets in one parse, in source order. A declaration without
/// `#serde.derive` is not one of them.
fn targets_of(decls : Array[@gen.Decl]) -> Array[Target] raise {
  let out = []
  for decl in decls {
    let place = place_of(decl)
    let attrs = decl.attrs()
    guard @attr.malformed(attrs, "serde").is_empty() else {
      raise refuse(place, "cannot make sense of a `#serde.` annotation")
    }
    for annotation in @attr.under(attrs, "serde") {
      let name = @attr.name_of(annotation).unwrap_or("")
      guard name == "serde.derive" else {
        raise refuse(place, "unknown annotation `#\{name}` on a type")
      }
    }
    guard @attr.find(attrs, "serde.derive") is Some(annotation) else {
      continue
    }
    let traits = arguments(derive_spec(), annotation, place).strs("trait")
    guard !traits.is_empty() else {
      raise refuse(place, "`#serde.derive` names no traits")
    }
    let mut serialize = false
    let mut deserialize = false
    for trait_ in traits {
      match trait_ {
        "Serialize" => serialize = true
        "Deserialize" => deserialize = true
        other =>
          raise refuse(
            place,
            "cannot derive `\{other}`; expected Serialize or Deserialize",
          )
      }
    }
    guard body_of(decl, place) is Some(body) else {
      raise refuse(
        place, "not a struct or an enum, so there is nothing to derive",
      )
    }
    out.push({
      name: decl.name(),
      params: decl.params(),
      public: decl.is_public(),
      body,
      serialize,
      deserialize,
    })
  }
  out
}

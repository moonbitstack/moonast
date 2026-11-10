///|
/// The code a generator writes for one file's worth of targets, as a template
/// each: the structure is written out and the names it carries are holes, so
/// quoting, escaping and layout stay with the printer. A list that varies with
/// the type — the cases of a match, the fields of a record, the statements of a
/// body — is a list hole, spliced with one code per item.
fn emit(targets : Array[Target]) -> @quote.Code raise {
  let out = []
  for target in targets {
    if target.serialize {
      out.push(serialize_of(target))
      out.push(extend_of(target, "Serialize"))
    }
    if target.deserialize {
      out.push(metadata_of(target))
      out.push(deserialize_of(target))
      out.push(extend_of(target, "Deserialize"))
    }
  }
  @quote.join(out)
}

///|
/// `template` with its named holes filled and its list holes spliced, rendered.
fn filled(
  template : @quote.Template,
  ones~ : Array[(String, @quote.Code)],
  spliced~ : Array[(String, Array[@quote.Code])] = [],
) -> @quote.Code raise {
  let mut out = template
  for pair in ones {
    out = out.set(pair.0, pair.1)
  }
  for pair in spliced {
    out = out.splice(pair.0, pair.1)
  }
  out.render()
}

///|
/// One expression, with the named holes it names and the list holes it splices.
fn expr(
  source : String,
  ones~ : Array[(String, @quote.Code)] = [],
  spliced~ : Array[(String, Array[@quote.Code])] = [],
) -> @quote.Code raise {
  filled(@quote.expr(source), ones~, spliced~)
}

///|
/// One match case, with the named holes it names and the cases it splices.
fn arm(
  source : String,
  ones~ : Array[(String, @quote.Code)] = [],
  spliced~ : Array[(String, Array[@quote.Code])] = [],
) -> @quote.Code raise {
  filled(@quote.cases(source), ones~, spliced~)
}

///|
/// One file of declarations, the same way.
fn decls(
  source : String,
  ones~ : Array[(String, @quote.Code)] = [],
  spliced~ : Array[(String, Array[@quote.Code])] = [],
) -> @quote.Code raise {
  filled(@quote.items(source), ones~, spliced~)
}

///|
/// `Pair[A, B]`, or `Pair` when it is not generic.
fn self_type(target : Target) -> String {
  if target.params.is_empty() {
    target.name
  } else {
    target.name + "[" + target.params.join(", ") + "]"
  }
}

///|
/// `pub impl[A : @serde.Serialize] @serde.Serialize for Pair[A]`.
fn impl_head(target : Target, trait_ : String) -> String {
  let visibility = if target.public { "pub " } else { "" }
  let bounds = if target.params.is_empty() {
    ""
  } else {
    "[" + target.params.map(p => p + " : @serde." + trait_).join(", ") + "]"
  }
  visibility +
  "impl" +
  bounds +
  " @serde." +
  trait_ +
  " for " +
  self_type(target) +
  " with fn "
}

///|
/// Whether the generated `serialize` reads the value at all. A type with nothing
/// left to write hands its parameter to no one, and an unused binding would warn
/// in a project that has no way to annotate a warning it did not write.
fn reads_self(target : Target) -> Bool {
  match target.body {
    Unit => false
    Newtype | Variants(_) => true
    Record(members) => members.iter().any(entry => !entry.skip)
    Tuple(arity) => arity > 0
  }
}

///|
fn kept(members : Array[Entry]) -> Array[Entry] {
  members.filter(entry => !entry.skip)
}

///|
/// `v0, v1, v2`.
fn binds_of(arity : Int32) -> String {
  Array::makei(arity, i => "v\{i}").join(", ")
}

///|
/// `@serde.VariantInfo::{ enum_name: "Shape", index: 3, name: "Tagged" }`.
fn variant_info(
  index : Int32,
  enum_name : String,
  name : String,
) -> @quote.Code raise {
  expr(
    "@serde.VariantInfo::{ enum_name: $enum_name, index: \{index}, name: $name }",
    ones=[
      ("enum_name", @quote.string(enum_name)),
      ("name", @quote.string(name)),
    ],
  )
}

///|
/// The name of the field identifier a record's members get.
fn record_identifier(target : Target) -> String {
  "DataRecordField\{target.name}"
}

///|
/// The name of the field identifier one variant's members get.
fn variant_identifier(target : Target, index : Int32) -> String {
  "DataVariantField\{target.name}\{index}"
}

///|
/// The name of the constant holding a record's field names.
fn record_names(target : Target) -> String {
  "__data_record_fields_\{target.name}"
}

///|
/// The name of the constant holding one variant's field names.
fn variant_names(target : Target, index : Int32) -> String {
  "__data_variant_fields_\{target.name}_\{index}"
}

///|
/// The name of the constant holding an enum's variant names.
fn case_names(target : Target) -> String {
  "__data_variants_\{target.name}"
}

///|
fn member_case(entry : Entry) -> String {
  "Field_\{entry.ident}"
}

///|
/// The bytes of `text` as a match pattern: `[0x6e, 0x61]`. The field identifier
/// fallback matches the key's bytes without going through a string.
fn byte_pattern(text : String) -> String {
  let out = StringBuilder()
  out.write_char('[')
  for i, byte in @utf8.encode(text) {
    if i > 0 {
      out.write_string(", ")
    }
    let n = byte.to_int()
    out.write_string("0x")
    out.write_char(hex_digit(n >> 4))
    out.write_char(hex_digit(n & 0x0F))
  }
  out.write_char(']')
  out.to_string()
}

///|
fn hex_digit(n : Int32) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('a'.to_int() + n - 10).unsafe_to_char()
  }
}

///|
fn serialize_of(target : Target) -> @quote.Code raise {
  let self = if reads_self(target) { "self" } else { "_self" }
  decls(
    impl_head(target, "Serialize") +
    "serialize($self, serializer) {\n  $body*\n}\n",
    ones=[("self", @quote.ident(self))],
    spliced=[("body", serialize_body(target))],
  )
}

///|
/// The statements a `serialize` is made of, one per line of its body.
fn serialize_body(target : Target) -> Array[@quote.Code] raise {
  match target.body {
    Unit =>
      [
        expr("serializer.serialize_unit_struct($name)", ones=[
          ("name", @quote.string(target.name)),
        ]),
      ]
    Newtype =>
      [
        expr("serializer.serialize_newtype_struct($name, self.0)", ones=[
          ("name", @quote.string(target.name)),
        ]),
      ]
    Record(members) => {
      let members = kept(members)
      let body = [
        expr("serializer.serialize_struct_begin($name, \{members.length()})", ones=[
          ("name", @quote.string(target.name)),
        ]),
      ]
      for entry in members {
        body.push(
          expr("serializer.serialize_field($key, self.$field)", ones=[
            ("key", @quote.string(entry.name)),
            ("field", @quote.ident(entry.ident)),
          ]),
        )
      }
      body.push(expr("serializer.serialize_struct_end()"))
      body
    }
    Tuple(arity) => {
      let body = [
        expr("serializer.serialize_tuple_struct_begin($name, \{arity})", ones=[
          ("name", @quote.string(target.name)),
        ]),
      ]
      for i in 0..<arity {
        body.push(expr("serializer.serialize_tuple_struct_field(self.\{i})"))
      }
      body.push(expr("serializer.serialize_tuple_struct_end()"))
      body
    }
    Variants(variants) => {
      let cases = []
      for index, variant in variants {
        cases.push(serialize_case(index, target, variant))
      }
      [expr("match self {\n  $cases* => ()\n}", spliced=[("cases", cases)])]
    }
  }
}

///|
/// One case of the `match self` a variant-shaped type is serialized with.
fn serialize_case(
  index : Int32,
  target : Target,
  variant : Variant,
) -> @quote.Code raise {
  let info = variant_info(index, target.name, variant.name)
  let who = @quote.ident(variant.ident)
  match variant.body {
    Unit =>
      arm("$Case => serializer.serialize_unit_variant($info)", ones=[
        ("Case", who),
        ("info", info),
      ])
    Newtype =>
      arm("$Case(v0) => serializer.serialize_newtype_variant($info, v0)", ones=[
        ("Case", who),
        ("info", info),
      ])
    Tuple(arity) => {
      let elements = []
      for i in 0..<arity {
        elements.push(expr("serializer.serialize_tuple_variant_element(v\{i})"))
      }
      arm(
        "$Case(\{binds_of(arity)}) => {\n  serializer.serialize_tuple_variant_begin($info, \{arity})\n  $elements*\n  serializer.serialize_tuple_variant_end()\n}",
        ones=[("Case", who), ("info", info)],
        spliced=[("elements", elements)],
      )
    }
    Record(members) => {
      let fields = []
      for i, entry in members {
        fields.push(
          expr("serializer.serialize_struct_variant_field($key, v\{i})", ones=[
            ("key", @quote.string(entry.name)),
          ]),
        )
      }
      let bound = members.mapi((i, entry) => "\{entry.ident}=v\{i}").join(", ")
      arm(
        "$Case(\{bound}) => {\n  serializer.serialize_struct_variant_begin($info, \{members.length()})\n  $fields*\n  serializer.serialize_struct_variant_end()\n}",
        ones=[("Case", who), ("info", info)],
        spliced=[("fields", fields)],
      )
    }
    Variants(_) => raise Bad(msg="internal: a variant holds no enum")
  }
}

///|
/// `let __data_record_fields_Point : ReadOnlyArray[String] = ["x", "y"]`, and for
/// an enum one constant of variant names plus one per payload that has fields.
fn metadata_of(target : Target) -> @quote.Code raise {
  match target.body {
    Record(members) =>
      @quote.join([
        names_of(record_names(target), members),
        field_identifier(record_identifier(target), members),
      ])
    Variants(variants) => {
      let names = []
      for variant in variants {
        names.push(@quote.string(variant.name))
      }
      let out = [
        decls(
          "let $name : ReadOnlyArray[String] = [$cases*]",
          ones=[("name", @quote.ident(case_names(target)))],
          spliced=[("cases", names)],
        ),
      ]
      for index, variant in variants {
        guard variant.body is Record(members) else { continue }
        out.push(names_of(variant_names(target, index), members))
        out.push(field_identifier(variant_identifier(target, index), members))
      }
      @quote.join(out)
    }
    _ => decls("")
  }
}

///|
/// The constant that holds a list of wire names.
fn names_of(name : String, members : Array[Entry]) -> @quote.Code raise {
  let names = []
  for entry in kept(members) {
    names.push(@quote.string(entry.name))
  }
  decls(
    "let $name : ReadOnlyArray[String] = [$names*]",
    ones=[("name", @quote.ident(name))],
    spliced=[("names", names)],
  )
}

///|
/// The `__Field` enum and the four reads of it: by index, by bytes with a hint,
/// by string, and back to the name.
fn field_identifier(
  identifier : String,
  members : Array[Entry],
) -> @quote.Code raise {
  let members = kept(members)
  let variants = members.map(member_case)
  variants.push("Unknown")
  let out = [decls("priv enum \{identifier} {\n  \{variants.join("\n  ")}\n}")]
  let head = "impl @serde.FieldIdentifier for \{identifier} with fn "
  out.push(
    decls(head + "from_index(index) {\n  $body*\n}", spliced=[
      ("body", [field_by_index(members)]),
    ]),
  )
  out.push(
    decls(head + "from_bytes(key, index_hint) {\n  $body*\n}", spliced=[
      ("body", [field_by_bytes(members)]),
    ]),
  )
  out.push(
    decls(head + "from_string(name) {\n  $body*\n}", spliced=[
      ("body", [field_by_string(members)]),
    ]),
  )
  out.push(
    decls(head + "name(self) {\n  $body*\n}", spliced=[
      ("body", [field_name(members)]),
    ]),
  )
  @quote.join(out)
}

///|
/// `match index { 0 => Field_x … _ => Unknown }`, or `Unknown` when there is no
/// field to name.
fn field_by_index(members : Array[Entry]) -> @quote.Code raise {
  guard !members.is_empty() else { return expr("Unknown") }
  let cases = []
  for index, entry in members {
    cases.push(
      arm("\{index} => $case", ones=[("case", @quote.ident(member_case(entry)))]),
    )
  }
  cases.push(arm("_ => Unknown"))
  expr("match index {\n  $cases* => ()\n}", spliced=[("cases", cases)])
}

///|
/// The hint is tried first, then the key's own bytes: a format that sends the
/// name as bytes still finds the field without building a string.
fn field_by_bytes(members : Array[Entry]) -> @quote.Code raise {
  guard !members.is_empty() else { return expr("Unknown") }
  let hinted = []
  for index, entry in members {
    hinted.push(
      arm("\{index} if key.equal_to_bytes($bytes) => $case", ones=[
        ("bytes", @quote.bytes(entry.name)),
        ("case", @quote.ident(member_case(entry))),
      ]),
    )
  }
  let byte_cases = []
  for entry in members {
    byte_cases.push(
      arm("\{byte_pattern(entry.name)} => $case", ones=[
        ("case", @quote.ident(member_case(entry))),
      ]),
    )
  }
  byte_cases.push(arm("_ => Unknown"))
  hinted.push(
    arm("_ => match key {\n  $cases* => ()\n}", spliced=[("cases", byte_cases)]),
  )
  expr("match index_hint {\n  $cases* => ()\n}", spliced=[("cases", hinted)])
}

///|
fn field_by_string(members : Array[Entry]) -> @quote.Code raise {
  guard !members.is_empty() else { return expr("Unknown") }
  let cases = []
  for entry in members {
    cases.push(
      arm("$name => $case", ones=[
        ("name", @quote.string(entry.name)),
        ("case", @quote.ident(member_case(entry))),
      ]),
    )
  }
  cases.push(arm("_ => Unknown"))
  expr("match name {\n  $cases* => ()\n}", spliced=[("cases", cases)])
}

///|
fn field_name(members : Array[Entry]) -> @quote.Code raise {
  let cases = []
  for entry in members {
    cases.push(
      arm("$case => Some($name)", ones=[
        ("case", @quote.ident(member_case(entry))),
        ("name", @quote.string(entry.name)),
      ]),
    )
  }
  cases.push(arm("Unknown => None"))
  expr("match self {\n  $cases* => ()\n}", spliced=[("cases", cases)])
}

///|
/// The `extend` for the method an impl silently promotes. A trait impl installs
/// its methods on the type as well, so declaring it deprecated and hidden keeps a
/// derived `Serialize` out of the project's own interface while leaving the
/// promotion legal for anyone already reaching for it.
fn extend_of(target : Target, trait_ : String) -> @quote.Code raise {
  let called = if trait_ == "Serialize" { "serialize" } else { "deserialize" }
  let visibility = if target.public { "pub " } else { "" }
  decls(
    "#deprecated(\"reach it through the `\{trait_}` bound\", skip_current_package=true)\n#doc(hidden)\n\{visibility}extend $Type with @serde.$trait::{$called}\n",
    ones=[
      ("trait", @quote.ident(trait_)),
      ("Type", @quote.ident(target.name)),
      ("called", @quote.ident(called)),
    ],
  )
}

///|
fn deserialize_of(target : Target) -> @quote.Code raise {
  decls(
    impl_head(target, "Deserialize") +
    "deserialize(deserializer) {\n  $body*\n}\n",
    spliced=[("body", deserialize_body(target))],
  )
}

///|
fn deserialize_body(target : Target) -> Array[@quote.Code] raise {
  match target.body {
    Unit =>
      [
        expr("deserializer.deserialize_unit_struct($name)", ones=[
          ("name", @quote.string(target.name)),
        ]),
        expr("$Type::{ }", ones=[("Type", @quote.ident(target.name))]),
      ]
    Newtype =>
      [
        expr("$Type(deserializer.deserialize_newtype_struct($name))", ones=[
          ("Type", @quote.ident(target.name)),
          ("name", @quote.string(target.name)),
        ]),
      ]
    Record(members) => {
      let body = [
        expr("deserializer.deserialize_struct_begin($name, $fields)", ones=[
          ("name", @quote.string(target.name)),
          ("fields", @quote.ident(record_names(target))),
        ]),
      ]
      let reads = members_read(kept(members), record_identifier(target))
      for read in reads {
        body.push(read)
      }
      body.push(record_construction(members))
      body
    }
    Tuple(arity) => {
      let body = [
        expr("deserializer.deserialize_tuple_struct_begin($name, \{arity})", ones=[
          ("name", @quote.string(target.name)),
        ]),
      ]
      for i in 0..<arity {
        body.push(expr("let v\{i} = deserializer.deserialize_tuple_next()"))
      }
      body.push(expr("deserializer.deserialize_tuple_end()"))
      body.push(
        expr("$Type(\{binds_of(arity)})", ones=[
          ("Type", @quote.ident(target.name)),
        ]),
      )
      body
    }
    Variants(variants) => {
      let cases = []
      for index, variant in variants {
        cases.push(deserialize_case(index, target, variant))
      }
      cases.push(
        arm(
          "index => raise @serde.UnknownVariant(path=deserializer.path(), variant=index.to_string(), expected=$names)",
          ones=[("names", @quote.ident(case_names(target)))],
        ),
      )
      [
        expr(
          "let value = match deserializer.deserialize_enum_begin($name, $names) {\n  $cases* => ()\n}",
          ones=[
            ("name", @quote.string(target.name)),
            ("names", @quote.ident(case_names(target))),
          ],
          spliced=[("cases", cases)],
        ),
        expr("deserializer.deserialize_enum_end()"),
        expr("value"),
      ]
    }
  }
}

///|
/// One case of the `match` a variant-shaped type is deserialized with.
fn deserialize_case(
  index : Int32,
  target : Target,
  variant : Variant,
) -> @quote.Code raise {
  let who = @quote.ident(variant.ident)
  match variant.body {
    Unit =>
      arm(
        "\{index} => {\n  deserializer.deserialize_unit_variant()\n  $value\n}",
        ones=[("value", who)],
      )
    Newtype =>
      arm("\{index} => $Type(deserializer.deserialize_newtype_variant())", ones=[
        ("Type", who),
      ])
    Tuple(arity) => {
      let steps = []
      for i in 0..<arity {
        steps.push(expr("let v\{i} = deserializer.deserialize_tuple_next()"))
      }
      arm(
        "\{index} => {\n  deserializer.deserialize_tuple_begin(\{arity})\n  $steps*\n  deserializer.deserialize_tuple_end()\n  $Type(\{binds_of(arity)})\n}",
        ones=[("Type", who)],
        spliced=[("steps", steps)],
      )
    }
    Record(members) => {
      let steps = members_read(members, variant_identifier(target, index))
      steps.push(variant_construction(variant.ident, members))
      arm(
        "\{index} => {\n  deserializer.deserialize_struct_begin($name, $fields)\n  $steps*\n}",
        ones=[
          ("name", @quote.string(variant.name)),
          ("fields", @quote.ident(variant_names(target, index))),
        ],
        spliced=[("steps", steps)],
      )
    }
    Variants(_) => raise Bad(msg="internal: a variant holds no enum")
  }
}

///|
/// The accumulators and the loop that fills them, shared by records and the
/// struct-shaped variants.
fn members_read(
  members : Array[Entry],
  identifier : String,
) -> Array[@quote.Code] raise {
  let out = []
  for entry in members {
    out.push(
      expr("let mut $field = None", ones=[
        ("field", @quote.ident(accumulator(entry))),
      ]),
    )
  }
  let cases = []
  for entry in members {
    // An `Option` field takes the read straight, so an absent field and an
    // explicit null both land on `None`; anything else is wrapped so that
    // absence stays distinguishable and can be reported by name.
    let read = if entry.optional {
      "deserializer.deserialize_field_value()"
    } else {
      "Some(deserializer.deserialize_field_value())"
    }
    cases.push(
      arm("$case => $field = \{read}", ones=[
        ("case", @quote.ident(member_case(entry))),
        ("field", @quote.ident(accumulator(entry))),
      ]),
    )
  }
  cases.push(arm("Unknown => deserializer.skip_value()"))
  out.push(
    expr(
      "while (deserializer.deserialize_field() : $Identifier?) is Some(field) {\n  match field {\n    $cases* => ()\n  }\n}",
      ones=[("Identifier", @quote.ident(identifier))],
      spliced=[("cases", cases)],
    ),
  )
  out
}

///|
fn accumulator(entry : Entry) -> String {
  "f_" + entry.ident
}

///|
/// The value one entry contributes, reading its accumulator.
fn value_of(entry : Entry) -> @quote.Code raise {
  if entry.skip {
    return expr("Default::default()")
  }
  if entry.optional {
    return expr("$field", ones=[("field", @quote.ident(accumulator(entry)))])
  }
  expr(
    "match $field {\n  Some(value) => value\n  None => @serde.required(None, name=$name, path=deserializer.path())\n}",
    ones=[
      ("field", @quote.ident(accumulator(entry))),
      ("name", @quote.string(entry.name)),
    ],
  )
}

///|
/// `label: value` for one member, the unit a field list is made of.
fn field_code(entry : Entry) -> @quote.Code raise {
  filled(@quote.fields("$label: $value"), ones=[
    ("label", @quote.ident(entry.ident)),
    ("value", value_of(entry)),
  ])
}

///|
/// `{ x: …, y: … }`, the value a record type reads back into.
fn record_construction(members : Array[Entry]) -> @quote.Code raise {
  expr("{\n  $fields*\n}", spliced=[("fields", members.map(field_code))])
}

///|
/// `Tagged(name=…, size=…)`: the same fields, spliced where a constructor's
/// labelled arguments go.
fn variant_construction(
  name : String,
  members : Array[Entry],
) -> @quote.Code raise {
  expr("$Type($fields*)", ones=[("Type", @quote.ident(name))], spliced=[
    ("fields", members.map(field_code)),
  ])
}

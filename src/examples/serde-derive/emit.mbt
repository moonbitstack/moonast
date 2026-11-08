///|
/// The code a generator writes for one file's worth of targets, as a template
/// each: the structure is written out and the names it carries are holes, so
/// quoting, escaping and layout stay with the printer.
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
/// Fill `$s0`, `$s1`, … with what the structure leaves open, in the order they
/// appear.
fn code(source : String, fills : Array[@quote.Code]) -> @quote.Code raise {
  let mut template = @quote.items(source)
  for i, fill in fills {
    template = template.set("s\{i}", fill)
  }
  template.render()
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
  self_type(target)
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
/// `@serde.VariantInfo::{ enum_name: "Shape", index: 3, name: "Tagged" }`, as
/// source, with its two strings left for the fills numbered `base` and `base + 1`.
fn variant_info(index : Int32, base : Int32) -> String {
  "@serde.VariantInfo::{ enum_name: $s\{base}, index: \{index}, name: $s\{base + 1} }"
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
  let out = StringBuilder()
  out.write_string(
    impl_head(target, "Serialize") +
    " with fn serialize(" +
    self +
    ", serializer) {\n",
  )
  let fills = []
  match target.body {
    Unit => {
      out.write_string("  serializer.serialize_unit_struct($s0)\n")
      fills.push(@quote.string(target.name))
    }
    Newtype => {
      out.write_string("  serializer.serialize_newtype_struct($s0, self.0)\n")
      fills.push(@quote.string(target.name))
    }
    Record(members) => {
      let members = kept(members)
      out.write_string(
        "  serializer.serialize_struct_begin($s0, \{members.length()})\n",
      )
      fills.push(@quote.string(target.name))
      for entry in members {
        out.write_string(
          "  serializer.serialize_field($s\{fills.length()}, self.\{entry.ident})\n",
        )
        fills.push(@quote.string(entry.name))
      }
      out.write_string("  serializer.serialize_struct_end()\n")
    }
    Tuple(arity) => {
      out.write_string(
        "  serializer.serialize_tuple_struct_begin($s0, \{arity})\n",
      )
      fills.push(@quote.string(target.name))
      for i in 0..<arity {
        out.write_string(
          "  serializer.serialize_tuple_struct_field(self.\{i})\n",
        )
      }
      out.write_string("  serializer.serialize_tuple_struct_end()\n")
    }
    Variants(variants) => {
      out.write_string("  match self {\n")
      for index, variant in variants {
        let info = variant_info(index, fills.length())
        match variant.body {
          Unit => {
            fills.push(@quote.string(target.name))
            fills.push(@quote.string(variant.name))
            out.write_string(
              "    \{variant.ident} => serializer.serialize_unit_variant(\{info})\n",
            )
          }
          Newtype => {
            fills.push(@quote.string(target.name))
            fills.push(@quote.string(variant.name))
            out.write_string(
              "    \{variant.ident}(v0) => serializer.serialize_newtype_variant(\{info}, v0)\n",
            )
          }
          Tuple(arity) => {
            let binds = binds_of(arity)
            out.write_string("    \{variant.ident}(\{binds}) => {\n")
            fills.push(@quote.string(target.name))
            fills.push(@quote.string(variant.name))
            out.write_string(
              "      serializer.serialize_tuple_variant_begin(\{info}, \{arity})\n",
            )
            for i in 0..<arity {
              out.write_string(
                "      serializer.serialize_tuple_variant_element(v\{i})\n",
              )
            }
            out.write_string("      serializer.serialize_tuple_variant_end()\n")
            out.write_string("    }\n")
          }
          Record(members) => {
            let bound = members.mapi((i, entry) => "\{entry.ident}=v\{i}")
            out.write_string("    \{variant.ident}(\{bound.join(", ")}) => {\n")
            fills.push(@quote.string(target.name))
            fills.push(@quote.string(variant.name))
            out.write_string(
              "      serializer.serialize_struct_variant_begin(\{info}, \{members.length()})\n",
            )
            for i, entry in members {
              out.write_string(
                "      serializer.serialize_struct_variant_field($s\{fills.length()}, v\{i})\n",
              )
              fills.push(@quote.string(entry.name))
            }
            out.write_string(
              "      serializer.serialize_struct_variant_end()\n",
            )
            out.write_string("    }\n")
          }
          Variants(_) => raise Bad(at="internal", msg="a variant holds no enum")
        }
      }
      out.write_string("  }\n")
    }
  }
  out.write_string("}\n")
  code(out.to_string(), fills)
}

///|
/// `v0, v1, v2`.
fn binds_of(arity : Int32) -> String {
  Array::makei(arity, i => "v\{i}").join(", ")
}

///|
/// `let __data_record_fields_Point : ReadOnlyArray[String] = ["x", "y"]`, and for
/// an enum one constant of variant names plus one per payload that has fields.
fn metadata_of(target : Target) -> @quote.Code raise {
  let out = StringBuilder()
  let fills = []
  match target.body {
    Record(members) => {
      let members = kept(members)
      out.write_string(
        "let \{record_names(target)} : ReadOnlyArray[String] = [",
      )
      out.write_string(names_source(members, fills))
      out.write_string("]\n")
      field_identifier(out, record_identifier(target), members, fills)
    }
    Variants(variants) => {
      out.write_string("let \{case_names(target)} : ReadOnlyArray[String] = [")
      for index, variant in variants {
        if index > 0 {
          out.write_string(", ")
        }
        out.write_string("$s\{fills.length()}")
        fills.push(@quote.string(variant.name))
      }
      out.write_string("]\n")
      for index, variant in variants {
        match variant.body {
          Record(members) => {
            out.write_string(
              "let \{variant_names(target, index)} : ReadOnlyArray[String] = [",
            )
            out.write_string(names_source(members, fills))
            out.write_string("]\n")
            field_identifier(
              out,
              variant_identifier(target, index),
              members,
              fills,
            )
          }
          _ => ()
        }
      }
    }
    _ => return code("", fills)
  }
  code(out.to_string(), fills)
}

///|
/// The entry names as string literals, comma separated, each one a fill.
fn names_source(members : Array[Entry], fills : Array[@quote.Code]) -> String {
  let parts = []
  for entry in kept(members) {
    parts.push("$s\{fills.length()}")
    fills.push(@quote.string(entry.name))
  }
  parts.join(", ")
}

///|
/// The `__Field` enum and the four reads of it: by index, by bytes with a hint,
/// by string, and back to the name.
fn field_identifier(
  out : StringBuilder,
  identifier : String,
  members : Array[Entry],
  fills : Array[@quote.Code],
) -> Unit {
  let members = kept(members)
  out.write_string("priv enum \{identifier} {\n")
  for entry in members {
    out.write_string("  \{member_case(entry)}\n")
  }
  out.write_string("  Unknown\n}\n")

  let head = "impl @serde.FieldIdentifier for \{identifier} with fn "
  out.write_string("\{head}from_index(index) {\n")
  if members.is_empty() {
    out.write_string("  Unknown\n")
  } else {
    out.write_string("  match index {\n")
    for index, entry in members {
      out.write_string("    \{index} => \{member_case(entry)}\n")
    }
    out.write_string("    _ => Unknown\n  }\n")
  }
  out.write_string("}\n")

  out.write_string("\{head}from_bytes(key, index_hint) {\n")
  if members.is_empty() {
    out.write_string("  Unknown\n")
  } else {
    out.write_string("  match index_hint {\n")
    for index, entry in members {
      out.write_string(
        "    \{index} if key.equal_to_bytes($s\{fills.length()}) => \{member_case(entry)}\n",
      )
      fills.push(@quote.bytes(entry.name))
    }
    out.write_string("    _ =>\n      match key {\n")
    for entry in members {
      out.write_string(
        "        \{byte_pattern(entry.name)} => \{member_case(entry)}\n",
      )
    }
    out.write_string("        _ => Unknown\n      }\n  }\n")
  }
  out.write_string("}\n")

  out.write_string("\{head}from_string(name) {\n")
  if members.is_empty() {
    out.write_string("  Unknown\n")
  } else {
    out.write_string("  match name {\n")
    for entry in members {
      out.write_string("    $s\{fills.length()} => \{member_case(entry)}\n")
      fills.push(@quote.string(entry.name))
    }
    out.write_string("    _ => Unknown\n  }\n")
  }
  out.write_string("}\n")

  out.write_string("\{head}name(self) {\n  match self {\n")
  for entry in members {
    out.write_string("    \{member_case(entry)} => Some($s\{fills.length()})\n")
    fills.push(@quote.string(entry.name))
  }
  out.write_string("    Unknown => None\n  }\n}\n")
}

///|
/// The `extend` for the method an impl silently promotes. A trait impl installs
/// its methods on the type as well, so declaring it deprecated and hidden keeps a
/// derived `Serialize` out of the project's own interface while leaving the
/// promotion legal for anyone already reaching for it.
fn extend_of(target : Target, trait_ : String) -> @quote.Code raise {
  let called = if trait_ == "Serialize" { "serialize" } else { "deserialize" }
  let visibility = if target.public { "pub " } else { "" }
  code(
    "#deprecated(\"reach it through the `\{trait_}` bound\", skip_current_package=true)\n" +
    "#doc(hidden)\n" +
    "\{visibility}extend \{target.name} with @serde.\{trait_}::{\{called}}\n",
    [],
  )
}

///|
fn deserialize_of(target : Target) -> @quote.Code raise {
  let out = StringBuilder()
  let fills = []
  out.write_string(
    impl_head(target, "Deserialize") + " with fn deserialize(deserializer) {\n",
  )
  let unit = () => {
    out.write_string(
      "  deserializer.deserialize_unit_struct($s\{fills.length()})\n",
    )
    fills.push(@quote.string(target.name))
  }
  match target.body {
    Unit => {
      unit()
      out.write_string("  \{target.name}::{ }\n")
    }
    Newtype => {
      out.write_string(
        "  \{target.name}(deserializer.deserialize_newtype_struct($s\{fills.length()}))\n",
      )
      fills.push(@quote.string(target.name))
    }
    Record(members) => {
      out.write_string(
        "  deserializer.deserialize_struct_begin($s\{fills.length()}, \{record_names(target)})\n",
      )
      fills.push(@quote.string(target.name))
      members_read(out, members, record_identifier(target), "")
      record_built(out, members, target.name, "", fills)
    }
    Tuple(arity) => {
      out.write_string(
        "  deserializer.deserialize_tuple_struct_begin($s\{fills.length()}, \{arity})\n",
      )
      fills.push(@quote.string(target.name))
      for i in 0..<arity {
        out.write_string(
          "  let v\{i} = deserializer.deserialize_tuple_next()\n",
        )
      }
      out.write_string("  deserializer.deserialize_tuple_end()\n")
      out.write_string("  \{target.name}(\{binds_of(arity)})\n")
    }
    Variants(variants) => {
      out.write_string(
        "  let value = match deserializer.deserialize_enum_begin($s\{fills.length()}, \{case_names(target)}) {\n",
      )
      fills.push(@quote.string(target.name))
      for index, variant in variants {
        match variant.body {
          Unit => {
            out.write_string("    \{index} => {\n")
            out.write_string("      deserializer.deserialize_unit_variant()\n")
            out.write_string("      \{variant.ident}\n")
            out.write_string("    }\n")
          }
          Newtype =>
            out.write_string(
              "    \{index} => \{variant.ident}(deserializer.deserialize_newtype_variant())\n",
            )
          Tuple(arity) => {
            out.write_string("    \{index} => {\n")
            out.write_string(
              "      deserializer.deserialize_tuple_begin(\{arity})\n",
            )
            for i in 0..<arity {
              out.write_string(
                "      let v\{i} = deserializer.deserialize_tuple_next()\n",
              )
            }
            out.write_string("      deserializer.deserialize_tuple_end()\n")
            out.write_string("      \{variant.ident}(\{binds_of(arity)})\n")
            out.write_string("    }\n")
          }
          Record(members) => {
            out.write_string("    \{index} => {\n")
            out.write_string(
              "      deserializer.deserialize_struct_begin($s\{fills.length()}, \{variant_names(target, index)})\n",
            )
            fills.push(@quote.string(variant.name))
            members_read(out, members, variant_identifier(target, index), "  ")
            out.write_string("      \{variant.ident}(\n")
            for entry in members {
              out.write_string(
                "        \{entry.ident}=\{value_source(entry, "        ", fills)},\n",
              )
            }
            out.write_string("      )\n")
            out.write_string("    }\n")
          }
          Variants(_) => raise Bad(at="internal", msg="a variant holds no enum")
        }
      }
      out.write_string(
        "    index => raise @serde.UnknownVariant(path=deserializer.path(), variant=index.to_string(), expected=\{case_names(target)})\n",
      )
      out.write_string("  }\n")
      out.write_string("  deserializer.deserialize_enum_end()\n")
      out.write_string("  value\n")
    }
  }
  out.write_string("}\n")
  code(out.to_string(), fills)
}

///|
/// The accumulators and the loop that fills them, shared by records and the
/// struct-shaped variants.
fn members_read(
  out : StringBuilder,
  members : Array[Entry],
  identifier : String,
  extra : String,
) -> Unit {
  for entry in kept(members) {
    out.write_string("\{extra}  let mut f_\{entry.ident} = None\n")
  }
  out.write_string(
    "\{extra}  while (deserializer.deserialize_field() : \{identifier}?) is Some(field) {\n",
  )
  out.write_string("\{extra}    match field {\n")
  for entry in kept(members) {
    // An `Option` field takes the read straight, so an absent field and an
    // explicit null both land on `None`; anything else is wrapped so that
    // absence stays distinguishable and can be reported by name.
    let read = if entry.optional {
      "deserializer.deserialize_field_value()"
    } else {
      "Some(deserializer.deserialize_field_value())"
    }
    out.write_string(
      "\{extra}      \{member_case(entry)} => f_\{entry.ident} = \{read}\n",
    )
  }
  out.write_string("\{extra}      Unknown => deserializer.skip_value()\n")
  out.write_string("\{extra}    }\n")
  out.write_string("\{extra}  }\n")
}

///|
/// The value one entry contributes, reading its accumulator.
fn value_source(
  entry : Entry,
  indent : String,
  fills : Array[@quote.Code],
) -> String {
  if entry.skip {
    "Default::default()"
  } else if entry.optional {
    "f_\{entry.ident}"
  } else {
    let name = "$s\{fills.length()}"
    fills.push(@quote.string(entry.name))
    "match f_\{entry.ident} {\n\{indent}  Some(value) => value\n\{indent}  None => @serde.required(None, name=\{name}, path=deserializer.path())\n\{indent}}"
  }
}

///|
/// `{ x: …, y: … }` for a record, or the variant's constructor call.
fn record_built(
  out : StringBuilder,
  members : Array[Entry],
  name : String,
  extra : String,
  fills : Array[@quote.Code],
) -> Unit {
  out.write_string("\{extra}  {\n")
  for entry in members {
    out.write_string(
      "\{extra}    \{entry.ident}: \{value_source(entry, extra + "    ", fills)},\n",
    )
  }
  out.write_string("\{extra}  }\n")
  ignore(name)
}

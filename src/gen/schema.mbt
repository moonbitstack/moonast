// The JSON Schema of a function's parameters, read off their MoonBit types and written as MoonBit
// source, for the generators that describe a function to something that calls it with JSON: a
// tool offered to a model, a handler offered over a protocol.

///|
/// The JSON Schema a value of type `ty` takes, as a MoonBit expression of type `Json` a generator
/// pastes into what it renders. Strings, the integer and floating types, `Bool` and `Unit` map to
/// their JSON types; `T?` and `Option[T]` add `null`; `Array`, `FixedArray` and `ReadOnlyArray`
/// are arrays of their element; `Map[K, V]` is an object of `V`. A type this does not know, a
/// record of the program's own, accepts any value and is left to its `FromJson`.
pub fn json_schema(ty : StringView) -> String {
  let ty = ty.trim(chars=" ").to_owned()
  if ty.has_suffix("?") {
    let inner = ty.exact_view(end=ty.length() - 1)
    return "{ \"anyOf\": [\{json_schema(inner)}, { \"type\": \"null\" }] }"
  }
  match type_args(ty) {
    Some(("Option", [inner])) =>
      "{ \"anyOf\": [\{json_schema(inner)}, { \"type\": \"null\" }] }"
    Some(("Array" | "FixedArray" | "ReadOnlyArray", [inner])) =>
      "{ \"type\": \"array\", \"items\": \{json_schema(inner)} }"
    Some(("Map", [_, inner])) =>
      "{ \"type\": \"object\", \"additionalProperties\": \{json_schema(inner)} }"
    _ =>
      match ty {
        "String" => "{ \"type\": \"string\" }"
        "Int"
        | "Int16"
        | "Int32"
        | "Int64"
        | "UInt"
        | "UInt16"
        | "UInt32"
        | "UInt64"
        | "Byte"
        | "BigInt" => "{ \"type\": \"integer\" }"
        "Double" | "Float" => "{ \"type\": \"number\" }"
        "Bool" => "{ \"type\": \"boolean\" }"
        "Unit" => "{ \"type\": \"null\" }"
        _ => "{}"
      }
  }
}

///|
/// `Name[A, B]` as its name and its arguments; a comma inside nested brackets stays with its
/// argument. `None` for a type without arguments.
pub fn type_args(ty : StringView) -> (String, Array[String])? {
  guard ty.find("[") is Some(open) && ty.has_suffix("]") else { return None }
  let name = ty.exact_view(end=open).to_owned()
  let inside = ty.exact_view(start=open + 1, end=ty.length() - 1)
  let args = []
  let mut depth = 0
  let mut from = 0
  for i, c in inside {
    match c {
      '[' => depth += 1
      ']' => depth -= 1
      ',' if depth == 0 => {
        args.push(
          inside.exact_view(start=from, end=i).trim(chars=" ").to_owned(),
        )
        from = i + 1
      }
      _ => ()
    }
  }
  args.push(inside.exact_view(start=from).trim(chars=" ").to_owned())
  Some((name, args))
}

///|
/// Whether a value of type `ty` may be absent: `T?` or `Option[T]`.
pub fn is_optional(ty : StringView) -> Bool {
  ty.has_suffix("?") || ty.has_prefix("Option[")
}

///|
/// Whether a caller has to give this parameter: one that is passed by position or by label and is
/// not of an optional type. An optional parameter and one with a default can be left out.
pub fn Param::required(self : Param) -> Bool {
  match self.pass {
    Positional | Labelled => !(self.ty is Some(ty) && is_optional(ty))
    Optional | Defaulted => false
  }
}

///|
/// The JSON Schema of the object a call of a function with `params` takes, as a MoonBit expression
/// of type `Json`: each parameter a property typed by `json_schema`, the ones `Param::required`
/// names listed as required. Every parameter needs a name and a type; a parameter without one
/// fails, naming `where_`.
pub fn object_schema(params : Array[Param], where_ : String) -> String raise {
  let props = []
  let required = []
  for param in params {
    guard param.name is Some(name) && param.ty is Some(ty) else {
      fail("\{where_}: every parameter needs a name and a type")
    }
    let key = @quote.string(name).to_string()
    props.push("\{key}: \{json_schema(ty)}")
    if param.required() {
      required.push(key)
    }
  }
  "{ \"type\": \"object\", \"properties\": { \{props.join(", ")} }, \"required\": [\{required.join(", ")}] }"
}

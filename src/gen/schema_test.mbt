///|
test "json_schema: a parameter's JSON type comes from its MoonBit type" {
  assert_eq(@gen.json_schema("String"), "{ \"type\": \"string\" }")
  assert_eq(@gen.json_schema(" Int64 "), "{ \"type\": \"integer\" }")
  assert_eq(@gen.json_schema("Double"), "{ \"type\": \"number\" }")
  assert_eq(
    @gen.json_schema("Array[Bool]"),
    "{ \"type\": \"array\", \"items\": { \"type\": \"boolean\" } }",
  )
  assert_eq(
    @gen.json_schema("Map[String, Array[Int]]"),
    "{ \"type\": \"object\", \"additionalProperties\": { \"type\": \"array\", \"items\": { \"type\": \"integer\" } } }",
  )
  assert_eq(
    @gen.json_schema("String?"),
    "{ \"anyOf\": [{ \"type\": \"string\" }, { \"type\": \"null\" }] }",
  )
  assert_eq(@gen.json_schema("Option[String]"), @gen.json_schema("String?"))
  // A record of the program's own is left to its `FromJson`.
  assert_eq(@gen.json_schema("Order"), "{}")
}

///|
test "type_args: a comma inside nested brackets stays with its argument" {
  assert_eq(
    @gen.type_args("Map[String, Map[Int, Bool]]"),
    Some(("Map", ["String", "Map[Int, Bool]"])),
  )
  assert_eq(@gen.type_args("Int"), None)
}

///|
test "object_schema: optional and defaulted parameters are left out of required" {
  let params : Array[@gen.Param] = [
    { name: Some("a"), ty: Some("Int"), pass: Positional, },
    { name: Some("b"), ty: Some("String?"), pass: Positional, },
    { name: Some("c"), ty: Some("Bool"), pass: Labelled, },
    { name: Some("d"), ty: Some("Double"), pass: Defaulted, },
    { name: Some("e"), ty: Some("String"), pass: Optional, },
  ]
  assert_eq(params.map(p => p.required()), [true, false, true, false, false])
  let schema = @gen.object_schema(params, "here")
  assert_true(schema.has_suffix("\"required\": [\"a\", \"c\"] }"))
  assert_true(schema.contains("\"d\": { \"type\": \"number\" }"))
}

///|
test "object_schema: a parameter without a name or a type is refused" {
  let refused = try {
    ignore(
      @gen.object_schema(
        [{ name: None, ty: Some("Int"), pass: Positional, }],
        "f.mbt:1:1",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

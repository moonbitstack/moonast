///|
fn refusal(render : () -> @quote.Code raise @quote.Refused) -> @quote.Refused? {
  try render() catch {
    e => Some(e)
  } noraise {
    _ => None
  }
}

///|
test "names, types and expressions fill their own positions" {
  let source =
    #|fn $name() -> $T {
    #|  $value
    #|}
  let code = @quote.items(source)
    .set("name", @quote.ident("answer"))
    .set("T", @quote.ident("Int"))
    .set("value", @quote.int(42))
    .render()
  inspect(
    code,
    content=(
      #|///|
      #|fn answer() -> Int {
      #|  42
      #|}
      #|
    ),
  )
}

///|
test "a hole inside a string literal is text, escaped when it is a string" {
  let source =
    #|fn greet() -> String {
    #|  "$who says $what"
    #|}
  let code = @quote.items(source)
    .set("who", @quote.ident("moonast"))
    .set("what", @quote.string("say \"hi\"\n"))
    .render()
  inspect(
    code,
    content=(
      #|///|
      #|fn greet() -> String {
      #|  "moonast says say \"hi\"\n"
      #|}
      #|
    ),
  )
}

///|
test "a string fills an expression hole as a literal" {
  let code = @quote.expr("label($text)")
    .set("text", @quote.string("tab\there"))
    .render()
  inspect(
    code,
    content=(
      #|label("tab\there")
    ),
  )
}

///|
test "a list hole expands among statements" {
  let source =
    #|fn write(self : $T, s : Sink) -> Unit {
    #|  s.begin("$T")
    #|  $fields*
    #|  s.end()
    #|}
  let fields = ["x", "y"].map(name => {
    @quote.expr("s.field(\"$key\", self.$name)")
    .set("key", @quote.string(name))
    .set("name", @quote.ident(name))
    .render()
  })
  let code = @quote.items(source)
    .set("T", @quote.ident("Point"))
    .splice("fields", fields)
    .render()
  inspect(
    code,
    content=(
      #|///|
      #|fn write(self : Point, s : Sink) -> Unit {
      #|  s.begin("Point")
      #|  s.field("x", self.x)
      #|  s.field("y", self.y)
      #|  s.end()
      #|}
      #|
    ),
  )
}

///|
test "a list hole expands among array elements and positional arguments" {
  let names = [@quote.string("a"), @quote.string("b")]
  let code = @quote.expr("register($first, [$rest*], $more*)")
    .set("first", @quote.int(0))
    .splice("rest", names)
    .splice("more", [@quote.bool(true), @quote.ident("other")])
    .render()
  inspect(
    code,
    content=(
      #|register(0, ["a", "b"], true, other)
    ),
  )
}

///|
test "an empty list leaves the statements around it" {
  let source =
    #|fn f() -> Unit {
    #|  start()
    #|  $body*
    #|  stop()
    #|}
  inspect(
    @quote.items(source).splice("body", []).render(),
    content=(
      #|///|
      #|fn f() -> Unit {
      #|  start()
      #|  stop()
      #|}
      #|
    ),
  )
}

///|
test "a qualified name fills a type" {
  let code = @quote.items("fn handle(app : $App) -> Unit { () }")
    .set("App", @quote.ident("@moonapi.App"))
    .render()
  inspect(
    code,
    content=(
      #|///|
      #|fn handle(app : @moonapi.App) -> Unit {
      #|  ()
      #|}
      #|
    ),
  )
}

///|
test "a rendered type fills a type hole" {
  let element = @quote.ty("Map[String, $V]")
    .set("V", @quote.ident("Int"))
    .render()
  inspect(
    element,
    content=(
      #|Map[String, Int]
    ),
  )
  let code = @quote.items("fn f(x : Array[$E]) -> Unit { () }")
    .set("E", element)
    .render()
  inspect(
    code,
    content=(
      #|///|
      #|fn f(x : Array[Map[String, Int]]) -> Unit {
      #|  ()
      #|}
      #|
    ),
  )
}

///|
test "declarations join in order" {
  let a = @quote.items("fn a() -> Unit { () }").render()
  let b = @quote.items("fn b() -> Unit { () }").render()
  inspect(
    @quote.join([a, b]),
    content=(
      #|///|
      #|fn a() -> Unit {
      #|  ()
      #|}
      #|
      #|///|
      #|fn b() -> Unit {
      #|  ()
      #|}
      #|
    ),
  )
}

///|
test "two dollars are one" {
  inspect(
    @quote.expr("\"$$5\"").render(),
    content=(
      #|"$5"
    ),
  )
}

///|
test "a hole given nothing is refused" {
  guard refusal(() => @quote.items("fn $name() -> Unit { () }").render())
    is Some(e) else {
    fail("an empty hole renders")
  }
  inspect(e, content="hole $name was given nothing")
}

///|
test "a fill for a hole the template lacks is refused" {
  guard refusal(() => @quote.expr("1").set("missing", @quote.int(1)).render())
    is Some(e) else {
    fail("an unused fill renders")
  }
  inspect(e, content="the template has no hole $missing")
}

///|
test "a type in an expression position is refused" {
  let t = @quote.ty("Int").render()
  guard refusal(() => @quote.expr("f($x)").set("x", t).render()) is Some(e) else {
    fail("a type fills an expression")
  }
  inspect(e, content="hole $x takes an expression")
}

///|
test "a template that is not MoonBit is refused with its position" {
  guard refusal(() => @quote.items("fn ( -> Unit").render())
    is Some(Template(..)) else {
    fail("a broken template renders")
  }
}

///|
test "a name that is not an identifier is refused" {
  guard refusal(() => @quote.ident("1st")) is Some(e) else {
    fail("1st is an identifier")
  }
  inspect(e, content="1st is not an identifier")
  guard refusal(() => @quote.ident("@pkg.ok")) is None else {
    fail("a qualified name is refused")
  }
}

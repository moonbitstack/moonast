///|
/// The six forms of a hole, as the guide's table lists them. Each row of that
/// table is one inspection here, so a change in the scanner shows up as a
/// failing page.
test "the six forms of a hole" {
  // $T — a type or a constructor.
  inspect(
    @quote.items("fn f(x : $T) -> Unit {\n  ignore(x)\n}")
    .set("T", @quote.ident("Int"))
    .render()
    .to_string(),
    content="///|\nfn f(x : Int) -> Unit {\n  ignore(x)\n}\n",
  )
  // $name — a value, an expression, or a name.
  inspect(
    @quote.expr("$value + 1").set("value", @quote.int(41)).render().to_string(),
    content="41 + 1",
  )
  // @pkg.$name — a name inside a package.
  inspect(
    @quote.ty("@web.$T").set("T", @quote.ident("App")).render().to_string(),
    content="@web.App",
  )
  // $name* — a list.
  inspect(
    @quote.expr("[$items*]")
    .splice("items", [@quote.int(1), @quote.int(2), @quote.int(3)])
    .render()
    .to_string(),
    content="[1, 2, 3]",
  )
  // $name in a string — text.
  inspect(
    @quote.items("fn f() -> String { \"field $key\" }")
    .set("key", @quote.string("first name"))
    .render()
    .to_string(),
    content="///|\nfn f() -> String {\n  \"field first name\"\n}\n",
  )
  // $$ — a literal dollar sign.
  inspect(@quote.expr("\"$$5\"").render().to_string(), content="\"$5\"")
}

///|
/// The guide's last hole example: text with Chinese in it goes through the
/// official escaping, so the literal in the output is a literal one can live
/// with.
test "a label in Chinese survives quoting" {
  inspect(
    @quote.items("fn label() -> String { $text }")
    .set("text", @quote.string("坐标：x 与 y"))
    .render()
    .to_string(),
    content="///|\nfn label() -> String {\n  \"坐标：x 与 y\"\n}\n",
  )
}

///|
/// The guide's "a template on its own" example, end to end: no generator
/// binary, just a template and three fills.
test "a template used without a generator" {
  let source =
    #|fn $T::$field(self : $T) -> $Ty {
    #|  self.$field
    #|}
  let code = @quote.items(source)
    .set("T", @quote.ident("User"))
    .set("field", @quote.ident("id"))
    .set("Ty", @quote.ty("Int").render())
    .render()
  inspect(
    code.to_string(),
    content=(
      #|///|
      #|fn User::id(self : User) -> Int {
      #|  self.id
      #|}
      #|
    ),
  )
}

///|
/// The guide's statement that a list hole among statements expands in place.
test "a list hole among statements keeps its order" {
  inspect(
    @quote.items("fn main {\n  $body*\n}")
    .splice("body", [
      @quote.expr("println(1)").render(),
      @quote.expr("println(2)").render(),
    ])
    .render()
    .to_string(),
    content="///|\nfn main {\n  println(1)\n  println(2)\n}\n",
  )
}

///|
/// The refusals the guide's table names, in the words it prints.
test "the refusal messages the guide prints" {
  let unfilled = @quote.items("fn $name() -> Unit { () }").render().to_string() catch {
      e => e.to_string()
    }
  inspect(unfilled, content="hole $name was given nothing")
  let unused = @quote.items("fn f() -> Unit { () }")
    .set("x", @quote.int(1))
    .render()
    .to_string() catch {
      e => e.to_string()
    }
  inspect(unused, content="the template has no hole $x")
  let not_decls = @quote.join([@quote.expr("1").render()]).to_string() catch {
    e => e.to_string()
  }
  inspect(not_decls, content="expected declarations")
}

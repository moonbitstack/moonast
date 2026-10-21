///|
fn main {
  let source =
    #|fn $name() -> $T {
    #|  $value
    #|}
  let code = @quote.items(source)
    .set("name", @quote.ident("answer"))
    .set("T", @quote.ident("Int"))
    .set("value", @quote.int(42))
    .render() catch {
      e => abort("the tour's template renders: \{e}")
    }
  println(code)
}

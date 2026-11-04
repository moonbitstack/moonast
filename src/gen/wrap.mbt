///|
/// A parameter as a wrapper's signature declares it: `a : Int`, `a~ : Int`, `a? : Int`. A parameter
/// with a default comes out optional, since the default itself stays with the function being
/// wrapped. `None` when it has no name or no type, so there is nothing to pass along.
///
/// ```mbt check
/// test {
///   guard @gen.read(
///       "m.mbt", "fn f(a : Int, b~ : String, c~ : Bool = true) -> Unit {}",
///     )
///     is [Func(params~, ..)] else {
///     abort("a function")
///   }
///   inspect(
///     params.map(p => p.declared().unwrap_or("")).join(", "),
///     content="a : Int, b~ : String, c? : Bool",
///   )
///   inspect(
///     params.map(p => p.passed().unwrap_or("")).join(", "),
///     content="a, b~, c?",
///   )
/// }
/// ```
pub fn Param::declared(self : Param) -> String? {
  guard self.name is Some(name) && self.ty is Some(ty) else { return None }
  Some(
    match self.pass {
      Positional => "\{name} : \{ty}"
      Labelled => "\{name}~ : \{ty}"
      Optional | Defaulted => "\{name}? : \{ty}"
    },
  )
}

///|
/// A parameter as a wrapper passes it on: `a`, `a~`, `a?`. `None` when it has no name.
pub fn Param::passed(self : Param) -> String? {
  guard self.name is Some(name) else { return None }
  Some(
    match self.pass {
      Positional => name
      Labelled => "\{name}~"
      Optional | Defaulted => "\{name}?"
    },
  )
}

///|
/// What a function says after its return type, as source: empty, `raise`, `raise E` or `raise? E`,
/// so a wrapper can say the same. A type with arguments cannot be an error type, so the name is all
/// there is to print. Empty for anything that is not a function.
///
/// ```mbt check
/// test {
///   guard @gen.read("m.mbt", "fn f() -> Unit raise @a.Bad {}") is [decl] else {
///     abort("a function")
///   }
///   inspect(decl.raises(), content="raise @a.Bad")
/// }
/// ```
pub fn Decl::raises(self : Decl) -> String {
  let named = (ty : @syntax.Type) => {
    match ty {
      Name(constr_id~, ..) => long_name(constr_id.id)
      _ => "Error"
    }
  }
  match self.raw() {
    TopFuncDef(fun_decl~, ..) =>
      match fun_decl.error_type {
        NoErrorType | Noraise(..) => ""
        DefaultErrorType(..) => "raise"
        ErrorType(ty~) => "raise \{named(ty)}"
        MaybeError(ty~) => "raise? \{named(ty)}"
      }
    _ => ""
  }
}

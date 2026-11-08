///|
let list_users_command : @proton_contract.Command[Unit, Users] = contract.command("listUsers")

///|
let ping_command : @proton_contract.Command[Unit, Unit] = contract.command("ping")

///|
let create_user_command : @proton_contract.Command[Create, User] = contract.command("createUser")

///|
let registry_create_command : @proton_contract.Command[Create, User] = registry_contract.command("create")

///|
let registry_drop_command : @proton_contract.Command[Drop, Unit] = registry_contract.command("drop")

///|
#proton.command(contract=list_users_command)
fn list_users() -> Users {
  Users::{ items: [] }
}

///|
#proton.command(contract=ping_command)
fn ping(context : @proton.CommandContext) -> Unit {
  ignore(context)
}

///|
#proton.command(contract=create_user_command)
fn create_user(request : Create) -> User {
  ignore(request)
  User::{ id: 0 }
}

///|
#proton.command(contract=registry_create_command)
fn Registry::create(self : Registry, context : @proton.CommandContext, request : Create) -> User {
  ignore((self, context, request))
  User::{ id: 0 }
}

///|
#proton.command(contract=registry_drop_command)
fn Registry::drop(self : Registry) -> Unit {
  ignore(self)
}

import
  std/macros,
  pkg/[seiryu],
  spellua/binding,
  std/typetraits

type
  LuaDriver* = ref object
    state*: LuaState

proc new*(T: type LuaDriver): T {.construct.} =
  result.state = newstate()
  result.state.openlibs()

proc loadFile*(driver: LuaDriver, filename: string) =
  if (driver.state.loadfile(filename.cstring) or driver.state.pcall(0, 0, 0)) != 0:
    let msg = driver.state.tostring(-1)
    raiseAssert("error" & ": " & $msg)

proc close*(driver: LuaDriver) =
  driver.state.close()

macro getNumber*(driver: LuaDriver, name: untyped): Number =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      defer:
        `driver`.state.pop(1)
      `driver`.state.getglobal(`nameStrLit`)
      `driver`.state.tonumber(-1)

macro getInteger*(driver: LuaDriver, name: untyped): Integer =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      defer:
        `driver`.state.pop(1)
      `driver`.state.getglobal(`nameStrLit`)
      `driver`.state.tointeger(-1)

macro getBoolean*(driver: LuaDriver, name: untyped): bool =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      defer:
        `driver`.state.pop(1)
      `driver`.state.getglobal(`nameStrLit`)
      `driver`.state.toboolean(-1) == 1

macro getString*(driver: LuaDriver, name: untyped): string =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      defer:
        `driver`.state.pop(1)
      `driver`.state.getglobal(`nameStrLit`)
      $`driver`.state.tostring(-1)

template bindNumber*(driver: LuaDriver, name: untyped): untyped =
  let name {.inject.} = driver.getNumber(name)

template bindInteger*(driver: LuaDriver, name: untyped): untyped =
  let name {.inject.} = driver.getInteger(name)

template bindBoolean*(driver: LuaDriver, name: untyped): untyped =
  let name {.inject.} = driver.getBoolean(name)

template bindString*(driver: LuaDriver, name: untyped): untyped =
  let name {.inject.} = driver.getString(name)

proc setBoolean*(driver: LuaDriver, name: string, value: bool) =
  driver.state.pushboolean(cast[cint](value))
  driver.state.setglobal(name)

proc setString*(driver: LuaDriver, name: string, value: string) =
  driver.state.pushstring(value.cstring)
  driver.state.setglobal(name)

proc setNumber*(driver: LuaDriver, name: string, value: float) =
  driver.state.pushnumber(value)
  driver.state.setglobal(name)

proc setInteger*(driver: LuaDriver, name: string, value: int) =
  driver.state.pushinteger(cast[cint](value))
  driver.state.setglobal(name)

macro setBindBoolean*(driver: LuaDriver, name: untyped) =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      `driver`.state.pushboolean(cast[cint](`name`))
      `driver`.state.setglobal(`nameStrLit`)

macro setBindString*(driver: LuaDriver, name: untyped) =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      `driver`.state.pushstring(`name`)
      `driver`.state.setglobal(`nameStrLit`)

macro setBindNumber*(driver: LuaDriver, name: untyped) =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      `driver`.state.pushnumber(cast[float](`name`))
      `driver`.state.setglobal(`nameStrLit`)

macro setBindInteger*(driver: LuaDriver, name: untyped) =
  let nameStrLit = name.strVal.newLit()
  return quote:
    block:
      `driver`.state.pushinteger(cast[cint](`name`))
      `driver`.state.setglobal(`nameStrLit`)

macro callRetImpl*(driver: LuaDriver, rettype: typedesc): untyped =
  result = newStmtList()
  if rettype.strVal == "bool":
    result.add quote do:
      let ret = `driver`.state.toboolean(-1) == 1
      `driver`.state.pop(1)
      ret
  elif rettype.strVal == "int":
    result.add quote do:
      let ret = `driver`.state.tointeger(-1)
      `driver`.state.pop(1)
      ret
  elif rettype.strVal == "float":
    result.add quote do:
      let ret = `driver`.state.tonumber(-1)
      `driver`.state.pop(1)
      ret
  elif rettype.strVal == "string":
    result.add quote do:
      let ret = `driver`.state.tostring(-1)
      `driver`.state.pop(1)
      ret
  else:
    raise newException(AssertionError, "unsupported type: " & $rettype)
  
# call with no return value
macro call*(driver: LuaDriver, rettype: untyped, funcname: cstring, args: varargs[typed]): untyped =
  let nargs = args.len
  result = newStmtList()
  result.add quote do:
    `driver`.state.getglobal(`funcname`)
  for arg in args:
    let t = arg.gettype.typeKind
    if t == ntyBool:
      result.add quote do:
        `driver`.state.pushboolean(cast[cint](`arg`))
    elif t == ntyInt:
      result.add quote do:
        `driver`.state.pushinteger(cast[cint](`arg`))
    elif t == ntyFloat:
      result.add quote do:
        `driver`.state.pushnumber(cast[float](`arg`))
    elif t == ntyString:
      result.add quote do:
        `driver`.state.pushstring((`arg`).cstring)
    else:
      raise newException(AssertionError, "unsupported type" & $t)
  if rettype.strVal == "void":
    result.add quote do:
      `driver`.state.call(cast[cint](`nargs`), 0)
  elif rettype.strVal in @["bool", "int", "float", "string"]:
    result.add quote do:
      `driver`.state.call(cast[cint](`nargs`), 1)
    result.add quote do:
      callRetImpl(`driver`, `rettype`)
  else:
    raise newException(AssertionError, "unsupported type" & $rettype)
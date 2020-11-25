import strutils
import argparse/backend; export backend

proc toVarname(x: string): string =
  ## Convert x to something suitable as a Nim identifier
  ## Replaces - with _ for instance
  x.replace("-", "_").strip(chars={'_'})

proc longAndShort(name1: string, name2: string): tuple[long: string, short: string] =
  var
    longname: string
    shortname: string
  if name2 == "":
    longname = name1
  else:
    if name1.len > name2.len:
      longname = name1
      shortname = name2
    else:
      longname = name2
      shortname = name1
  return (longname, shortname)

proc flag*(name1: string, name2 = "", multiple = false, help = "") {.compileTime.} =
  ## Add a boolean flag to this parser
  let names = longAndShort(name1, name2)
  let varname = names.long.toVarname()
  builderStack[^1].components.add Component(
    kind: ArgFlag,
    help: help,
    varname: varname,
    flagShort: names.short,
    flagLong: names.long,
    flagMultiple: multiple,
  )

proc option*(name1: string, name2 = "", help = "", default = "", env = "", multiple = false, choices: seq[string] = @[]) {.compileTime.} =
  ## Add an option to this parser
  let names = longAndShort(name1, name2)
  let varname = names.long.toVarname()
  builderStack[^1].components.add Component(
    kind: ArgOption,
    help: help,
    varname: varname,
    env: env,
    optShort: names.short,
    optLong: names.long,
    optMultiple: multiple,
    optDefault: if default == "": none[string]() else: some(default),
    optChoices: choices,
  )

proc arg*(varname: string, default = "", env = "", help = "", nargs = 1) {.compileTime.} =
  ## Add place-value argument to this parser
  ## 
  builderStack[^1].components.add Component(
    kind: ArgArgument,
    help: help,
    varname: varname,
    nargs: nargs,
    env: env,
    argDefault: if default == "": none[string]() else: some(default),
  )

proc help*(helptext: string) {.compileTime.} =
  ## Add help to this parser/subcommand
  builderStack[^1].help &= helptext

proc nohelpflag*() {.compileTime.} =
  ## Disable the automatic -h/--help flag
  builderStack[^1].components.del(0)

template run*(body: untyped): untyped =
  ## Add a run block to this command

template command*(name: string, group: string, content: untyped): untyped =
  ## Add a subcommand to this parser
  add_command(name, group) do:
    content

template command*(name: string, content: untyped): untyped =
  ## Add a subcommand to this parser
  command(name, "", content)

template newParser*(name: string, body: untyped): untyped =
  macro domkParser(): untyped =
    let res = mkParser(name, "", proc() = body, instantiate = true)
    newStmtList(
      res.types,
      res.procs,
      res.instance,
    )
  domkParser()

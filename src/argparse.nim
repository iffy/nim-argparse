import sequtils
import strutils
import macros
import strformat
import parseopt
import argparse/macrohelp

type
  ComponentKind = enum
    Flag
  
  Component = object
    varname*: string
    case kind*: ComponentKind
    of Flag:
      shortflag*: string
      longflag*: string
  
  Builder = object
    name*: string
    symbol*: string
    components*: seq[Component]


var builderstack {.global.} : seq[Builder] = @[]

proc newBuilder(name: string): Builder {.compileTime.} =
  result = Builder()
  result.name = name
  result.symbol = genSym(nskLet, "argparse").toStrLit.strVal

proc optsIdent(builder: Builder): NimNode =
  result = ident("Opts"&builder.symbol)

proc parserIdent(builder: Builder): NimNode =
  result = ident("Parser"&builder.symbol)

proc add(builder: var Builder, component: Component) {.compileTime.} =
  builder.components.add(component)

proc genHelp(builder: var Builder):string {.compileTime.} =
  ## Generate the usage/help text for the parser.
  result.add(builder.name)
  result.add("\L")
  var widths: seq[int]
  var rows: seq[seq[string]]
  for comp in builder.components:
    case comp.kind
    of Flag:
      var row: seq[string]

      var flag_parts: seq[string]
      if comp.shortflag != "":
        flag_parts.add("-" & comp.shortflag)
      if comp.longflag != "":
        flag_parts.add("--" & comp.longflag)
      
      row.add(flag_parts.join(", "))
      row.add("")
      rows.add(row)
  
  for row in rows:
    for i,col in row:
      if i >= widths.len:
        widths.add(0)
      if col.len > widths[i]:
        widths[i] = col.len
    # For now, just display everything space-separated
    result.add(row.join(" "))
    result.add("\L")


proc generateReturnType(builder: var Builder): NimNode {.compileTime.} =
  var objdef = newObjectTypeDef(builder.optsIdent.strVal)
  for component in builder.components:
    case component.kind
    of Flag:
      objdef.addObjectField(component.varname, "bool")
    else:
      error("Unknown component type " & component.kind.repr)
  result = objdef.root

proc handleShortOptions(builder: Builder): NimNode {.compileTime.} =
  var cs = newCaseStatement("key")
  cs.addElse(replaceNodes(quote do:
    echo "unknown flag: -" & key
  ))
  for comp in builder.components:
    let shortflag = comp.shortflag
    if shortflag != "":
      let varname = ident(comp.varname)
      cs.add(comp.shortflag, replaceNodes(quote do:
        result.`varname` = true
      ))
  result = cs.finalize()

proc handleLongOptions(builder: Builder): NimNode =
  var cs = newCaseStatement("key")
  cs.addElse(replaceNodes(quote do:
    echo "unknown flag: --" & key
  ))
  for comp in builder.components:
    let longflag = comp.longflag
    if longflag != "":
      let varname = ident(comp.varname)
      cs.add(comp.longflag, replaceNodes(quote do:
        result.`varname` = true
      ))
  result = cs.finalize()

proc genParseProc(builder: var Builder): NimNode {.compileTime.} =
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()
  var rep = replaceNodes(quote do:
    proc parse(p:`ParserIdent`, input:string):`OptsIdent` =
      result = `OptsIdent`()
      var p = initOptParser(input)
      for kind, key, val in p.getopt():
        case kind
        of cmdEnd:
          discard
        of cmdShortOption:
          insertshort
        of cmdLongOption:
          insertlong
        of cmdArgument:
          discard
  )
  var shorts = rep.getInsertionPoint("insertshort")
  var longs = rep.getInsertionPoint("insertlong")
  shorts.add(handleShortOptions(builder))
  longs.add(handleLongOptions(builder))
  result = rep

proc mkParser*(name: string, content: proc()): NimNode {.compileTime.} =
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  let parserIdent = builder.parserIdent()
  
  # Generate help
  let helptext = builder.genHelp()

  # Create the parser return type
  result.add(builder.generateReturnType())

  # Create the parser type
  result.add(replaceNodes(quote do:
    type
      `parserIdent` = object
        help*: string
  ))

  # Create the parse proc
  result.add(builder.genParseProc())

  # Instantiate a parser and return an instance
  result.add(replaceNodes(quote do:
    var parser = `parserIdent`()
    parser.help = `helptext`
    parser
  ))

proc stripHypens(s:string):string =
  s.strip(leading=true, chars={'-'})

proc toUnderscores(s:string):string =
  s.replace('-','_').strip(chars={'_'})


proc flag*(opt1: string, opt2: string = "") {.compileTime.} =
  var
    c = Component()
    varname: string
  c.kind = Flag

  if opt1.startsWith("--"):
    c.shortflag = opt2.stripHypens
    c.longflag = opt1.stripHypens
  else:
    c.shortflag = opt1.stripHypens
    c.longflag = opt2.stripHypens
  
  if c.longflag != "":
    c.varname = c.longflag.toUnderscores
  else:
    c.varname = c.shortflag.toUnderscores
  
  builderstack[^1].add(c)




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
    components*: seq[Component]


var builderstack {.global.} : seq[Builder] = @[]

proc newBuilder(name: string): Builder {.compileTime.} =
  result = Builder()
  result.name = name

proc add(builder: var Builder, component: Component) {.compileTime.} =
  builder.components.add(component)

proc generateHelp(builder: var Builder):string {.compileTime.} =
  ## Generate the usage/help text for the parser.
  result.add(builder.name)
  result.add("\L")
  for component in builder.components:
    var parts: seq[string]
    parts.add("-" & component.shortflag)
    result.add(parts.join(" "))
    result.add("\L")


proc generateReturnType(builder: var Builder): NimNode {.compileTime.} =
  var objdef = newObjectTypeDef("Opts")
  for component in builder.components:
    case component.kind
    of Flag:
      objdef.addObjectField(component.varname, "bool")
    else:
      error("Unknown component type " & component.kind.repr)
  result = objdef.root

proc genShortOf(component: Component): NimNode {.compileTime.} =
  ## Generate the case "of" statement for a component (if any)
  result = newEmptyNode()
  case component.kind
  of Flag:
    if component.shortflag != "":
      discard

proc handleShortOptions(builder: Builder): NimNode {.compileTime.} =
  var cs = newCaseStatement("key")
  cs.addElse(replaceNodes(quote do:
    echo "unknown flag: -" & key
  ))
  for comp in builder.components:
    let shortflag = comp.shortflag
    let identshortflag = ident(shortflag)
    cs.add(comp.shortflag, replaceNodes(quote do:
      result.`identshortflag` = true
    ))
  result = cs.finalize()

proc genParseProc(builder: var Builder): NimNode {.compileTime.} =
  var rep = replaceNodes(quote do:
    proc parse(p:Parser, input:string):Opts =
      result = Opts()
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
  result = rep

proc mkParser*(name: string, content: proc()): NimNode {.compileTime.} =
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  
  # Generate help
  let helptext = builder.generateHelp()

  # Create the parser return type
  result.add(builder.generateReturnType())

  # Create the parser type
  result.add(replaceNodes(quote do:
    type
      Parser = object
        help*: string
  ))

  # Create the parse proc
  result.add(builder.genParseProc())

  # Instantiate a parser and return an instance
  result.add(replaceNodes(quote do:
    var parser = Parser()
    parser.help = `helptext`
    parser
  ))

proc flag*(shortflag: string) {.compileTime.} =
  var component = Component()
  component.kind = Flag
  component.shortflag = shortflag.strip(leading=true, chars={'-'})
  component.varname = shortflag.replace('-','_').strip(chars = {'_'})
  builderstack[^1].add(component)




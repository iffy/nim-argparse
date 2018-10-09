import sequtils
import strutils
import macros
import strformat

type
  ComponentKind = enum
    Flag
  
  Component* = object
    varname*: string
    case kind*: ComponentKind
    of Flag:
      shortflag*: string
      longflag*: string
  
  OptBuilder* = object
    components*: seq[Component]

  OptParser*[T] = object

proc add(p: var OptBuilder, component: Component) =
  p.components.add(component)

# A global -- this feels gross
static:
  var
    builder_stack: seq[OptBuilder]

# macro defineTypes(name: string, b: OptBuilder): untyped =
#   echo "defineTypes"
#   echo "b ", b
#   result = newStmtList()

#   # type
#   var typesection = newNimNode(nnkTypeSection)
#   result.add(typesection)
  
#   var reclist = newNimNode(nnkRecList)
#   var typdef = newNimNode(nnkTypeDef)
#     .add(newIdentNode(name.strVal))
#     .add(newEmptyNode())
#     .add(newNimNode(nnkObjectTy)
#       .add(newEmptyNode())
#       .add(newEmptyNode())
#       .add(reclist))
#   typesection.add(typdef)

#   for child in b:
#     echo "child ", child

#   # echo "mkParser end"
#   # # var
#   # #   
#   # var var_section = newNimNode(nnkVarSection)
#   # result.add(var_section)
#   # var_section.add(newIdentDefs(
#   #   newIdentNode(parsername.strVal),
#   #   newNimNode(nnkBracketExpr).add(
#   #     newIdentNode("Parser"),
#   #     newIdentNode("ParserOpts")
#   #   ),
#   #   newEmptyNode(),
#   # ))
#   echo "startParser end"

macro doThing(base: NimNode, thing: untyped): NimNode =
  hint("doThing")
  thing

static:
  var lastcomponent: Component

macro mkParser*(name: string, body: untyped): untyped =
  hint("mkParser")
  result = newStmtList()
  # echo "body: ", body.toStrLit
  # echo "len: ", body.len
  
  # var builder = OptBuilder()
  # discard pushBuilder
  # discard body

  for i, child in body:
    hint("child " & i.intToStr) 
    result.add(child)
  
  hint("done with children")
  result.add(quote do:
    type
      Opts = object
    var p = OptParser[Opts]()
    p
  )

macro flag*(opt1: string, opt2: string = "", help:string = ""):untyped =
  ## Add a flag option to the option parser
  hint("running flag")
  var
    varname: string
    shortflag: string
    longflag: string
  if opt1.startsWith("--"):
    longflag = opt1
    shortflag = opt2
    varname = opt1.substr(2)
  elif opt2.startsWith("--"):
    longflag = opt2
    shortflag = opt1
    varname = opt2.substr(2)
  elif opt1.startsWith("-"):
    shortflag = opt1
    varname = opt1.substr(1)
  else:
    error("Must provide a - or -- prefixed string for a flag")

  var component = Component()
  component.kind = Flag
  component.varname = varname
  component.shortflag = shortflag
  component.longflag = longflag
  result = quote do:
    5
  # builder_stack[^1].add(component)
  hint("done with flag: " & component.repr)
  # result = quote do:
  #   echo "hi"


proc renderHelp*(p: OptParser):string =
  result.add("The help")

proc parse*[T](p: var OptParser[T], input: string): T =
  result = (a: true, foo: false)

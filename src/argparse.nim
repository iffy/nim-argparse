import sequtils
import strutils
import macros
import strformat
import parseopt

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

  ObjTypeDef = object
    root*: NimNode
    insertion*: NimNode

var builderstack {.global.} : seq[Builder] = @[]

proc sanitize(name:string):string =
  return name.replace(" ", "")

proc newBuilder(name: string): Builder {.compileTime.} =
  result = Builder()
  result.name = name

proc add(builder: var Builder, component: Component) {.compileTime.} =
  builder.components.add(component)

proc generateHelp(builder: var Builder):string {.compileTime.} =
  result.add(builder.name)
  result.add("\L")
  for component in builder.components:
    var parts: seq[string]
    parts.add(component.shortflag)
    result.add(parts.join(" "))
    result.add("\L")

proc newObjectTypeDef(name: string): ObjTypeDef {.compileTime.} =
  ## Creates:
  ## root ->
  ##            type
  ##              {name} = object
  ## insertion ->    ...
  ##
  var insertion = newNimNode(nnkRecList)
  var root = newNimNode(nnkTypeSection).add(
    newNimNode(nnkTypeDef).add(
      ident(name),
      newEmptyNode(),
      newNimNode(nnkObjectTy).add(
        newEmptyNode(),
        newEmptyNode(),
        insertion,
      )
    )
  )
  result = ObjTypeDef(root: root, insertion: insertion)

proc addObjectField(objtypedef: ObjTypeDef, name: string, kind: string) {.compileTime.} =
  ## Adds a field to an object definition created by newObjectTypeDef
  objtypedef.insertion.add(newIdentDefs(
    newNimNode(nnkPostfix).add(
      ident("*"),
      ident(name),
    ),
    ident(kind),
    newEmptyNode(),
  ))

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

proc genShortCase(builder: var Builder): NimNode {.compileTime.} =
  ## Generate the case statement for the short flag cases
  result = newNimNode(nnkCaseStmt).add(
    ident("key"),
  )
  for comp in builder.components:
    for o in comp.genShortOf():
      result.add(o)
  result.add(
    newNimNode(nnkElse).add(
      newStmtList(
        newNimNode(nnkCommand).add(
          ident("echo"),
          newStrLitNode("Unknown flag"),
        )
      )
    )
  )

template genParseProc(builder: var Builder):untyped =
  ## Generate the parse() proc
  proc parse(p:Parser, input:string):Opts =
    result = Opts()
    echo "parsing: ", input

proc instantiateParser(builder: var Builder): NimNode {.compileTime.} =
  result = newStmtList(
    # var parser = someParser()
    newNimNode(nnkVarSection).add(
      newIdentDefs(
        ident("parser"),
        newEmptyNode(),
        newCall("Parser"),
      )
    ),
    # parser.help = thehelptext
    newNimNode(nnkAsgn).add(
      newDotExpr(
        ident("parser"),
        ident("help"),
      ),
      newLit(builder.generateHelp()),
    ),
    # parser
    ident("parser"),
  )


proc mkParser*(name: string, content: proc()): NimNode {.compileTime.} =
  hint("mkParser start")
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  
  # Create the parser return type
  result.add(builder.generateReturnType())

  # Create the parser type
  # type
  #   Parser = object
  var parser = newObjectTypeDef("Parser")
  #     help*: string
  parser.addObjectField("help", "string")
  result.add(parser.root)

  # Create the parse proc
  result.add(getAst(genParseProc(builder)))

  # Instantiate a parser and return an instance
  result.add(builder.instantiateParser())
  hint("mkParser end")

proc flag*(shortflag: string) {.compileTime.} =
  var component = Component()
  component.kind = Flag
  component.shortflag = shortflag.strip(leading=true, chars={'-'})
  component.varname = shortflag.replace('-','_').strip(chars = {'_'})
  builderstack[^1].add(component)




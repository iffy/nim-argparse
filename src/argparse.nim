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

proc handleShortOptions(builder: Builder, key: string, val: string): NimNode {.compileTime.} =
  hint("in something macro")
  for comp in builder.components:
    echo "comp ", comp.repr
  result = quote do:
    echo "handling short option"
    echo "key ", `key`

proc parentOf(node: NimNode, name:string): NimNode {.compileTime.} =
  var stack:seq[NimNode] = @[node]
  while stack.len > 0:
    var n = stack.pop()
    echo "testing node: ", n.treeRepr
    for child in n.children:
      if child.kind == nnkIdent and child.strVal == name:
        return n
      else:
        stack.add(child)
  error("node not found: " & name)

macro captureAst(s: untyped):untyped =
  s.astGenRepr

proc genParseProc(builder: var Builder): NimNode {.compileTime.} =
  var rep = quote do:
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
  var i1 = rep.parentOf("insertshort")
  var i2 = rep.parentOf("insertlong")
  i1.del(n = i1.len)
  i2.del(n = i2.len)
  echo "insertion point 1: ", i1.astGenRepr
  echo "insertion point 2: ", i2.astGenRepr
  echo "rep: ", rep.astGenRepr
  result = newEmptyNode()

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
  result.add(builder.genParseProc())

  # Instantiate a parser and return an instance
  result.add(builder.instantiateParser())
  hint("mkParser end")

proc flag*(shortflag: string) {.compileTime.} =
  var component = Component()
  component.kind = Flag
  component.shortflag = shortflag.strip(leading=true, chars={'-'})
  component.varname = shortflag.replace('-','_').strip(chars = {'_'})
  builderstack[^1].add(component)




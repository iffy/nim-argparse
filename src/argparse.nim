import sequtils
import strutils
import macros
import strformat

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

  Parser = object
    help*: string

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
  var root = newStmtList(
    newNimNode(nnkTypeSection).add(
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

proc returnTypeName(builder: var Builder): string {.compileTime.} =
  builder.name & "opts"

proc generateReturnType(builder: var Builder): NimNode {.compileTime.} =
  let objname = builder.returnTypeName()
  var objdef = newObjectTypeDef(objname)

  for component in builder.components:
    case component.kind
    of Flag:
      objdef.addObjectField(component.varname, "bool")
    else:
      error("Unknown component type " & component.kind.repr)

  result = objdef.root

proc mkParser*(name: string, content: proc()): NimNode {.compileTime.} =
  hint("mkParser start")
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  var help = builder.generateHelp()
  let objname = builder.returnTypeName()
  # result.add(builder.generateReturnType())
  # result.add(quote do:
  #   type
  #     Parser = object
  #       help*: string
  # )
  result.add(quote do:
    type Foo = object
    var parser = Parser()
    parser.help = `help`
    parser
  )
  hint("mkParser end")

proc flag*(shortflag: string) {.compileTime.} =
  var component = Component()
  component.kind = Flag
  component.shortflag = shortflag
  component.varname = shortflag.replace('-','_').strip(chars = {'_'})
  builderstack[^1].add(component)




# macro handleParserComponents(body: untyped): untyped =
#   hint("handleParserComponents")
#   result = newStmtList()

# macro mkParser*(name: string, body: untyped): untyped =
#   hint("mkParser")
#   result = newStmtList()
#   var fields:seq[string]
#   fields.add("a*: bool")
#   fields.add("b*: bool")
#   fields.add("")
#   let fieldstr = fields.join("\L        ")
#   hint("fieldstr " & fieldstr)
#   let something = "a*: bool"
#   result.add(quote do:
#     echo "hi"
#     type
#       OptParser = object
#       Opts = object
#         a*: bool
#         b*: bool
#     proc parse(p: OptParser, input: string):Opts =
#       discard
    
#     var p = OptParser()
#     p
#   )
  
#   # handleParserComponents(body)

#   # result = newStmtList()
#   # for i, child in body:
#   #   hint("child " & i.intToStr) 
#     # result.add(child)
  
#   hint("done with children")
#   # var p = OptParser[string]()
#   # p

# # proc flag*(opt1: string) =
# #   ## Add a flag option to the option parser
# #   hint("running flag")
# #   var
# #     varname: string
# #     shortflag: string
# #   shortflag = opt1
# #   varname = opt1.substr(1)

# #   var component = Component()
# #   component.kind = Flag
# #   component.varname = varname
# #   component.shortflag = shortflag
# #   # builder_stack[^1].add(component)
# #   hint("done with flag: " & component.repr)
# #   # result = quote do:
# #   #   echo "hi"


# # proc renderHelp*(p: OptParser):string =
# #   result.add("The help")

proc parse*(p: Parser, input:string):untyped =
  return (a: true, b: true)
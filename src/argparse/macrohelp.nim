import macros
import strformat
import strutils
import sequtils

type
  UnfinishedObjectTypeDef* = object
    root*: NimNode
    insertion*: NimNode
  
  UnfinishedCase = object
    root*: NimNode
    cases*: seq[NimNode]
    elsebody*: NimNode
  
  UnfinishedIf = object
    root*: NimNode
    elsebody*: NimNode
  
  InsertionPoint = object
    parent: NimNode
    child: NimNode


proc replaceNodes*(ast: NimNode): NimNode =
  ## Replace NimIdent and NimSym by a fresh ident node
  ##
  ## Use with the results of ``quote do: ...`` to get
  ## ASTs without symbol resolution having been done already.
  proc inspect(node: NimNode): NimNode =
    case node.kind:
    of nnkIdent:
      return ident(node.strVal)
    of nnkSym:
      return ident(node.strVal)
    of nnkEmpty:
      return node
    of nnkLiterals:
      return node
    of nnkOpenSymChoice:
      return inspect(node[0])
    else:
      var rTree = node.kind.newTree()
      for child in node:
        rTree.add inspect(child)
      return rTree
  result = inspect(ast)

proc parentOf*(node: NimNode, name:string): InsertionPoint =
  ## Recursively search for an ident node of the given name and return
  ## the parent of that node.
  var stack:seq[NimNode] = @[node]
  while stack.len > 0:
    var n = stack.pop()
    for child in n.children:
      if child.kind == nnkIdent and child.strVal == name:
        return InsertionPoint(parent:n, child:child)
      else:
        stack.add(child)
  error("node not found: " & name)

proc getInsertionPoint*(node: var NimNode, name:string): InsertionPoint =
  ## Return a node pair that you can replace with something else
  return node.parentOf(name)

proc clear*(point: InsertionPoint):int =
  var i = 0
  for child in point.parent.children:
    if child == point.child:
      break
    inc(i)
  point.parent.del(i, 1)
  result = i

proc replace*(point: InsertionPoint, newnode: NimNode) =
  ## Replace the child
  let i = point.clear()
  point.parent.insert(i, newnode)

proc newObjectTypeDef*(name: string, isref:bool = false): UnfinishedObjectTypeDef {.compileTime.} =
  ## Creates:
  ## root ->
  ##            type
  ##              {name} = object
  ## insertion ->    ...
  ##
  var insertion = newNimNode(nnkRecList)
  var objectty = nnkObjectTy.newTree(
    newEmptyNode(),
    newEmptyNode(),
    insertion,
  )
  if isref:
    objectty = nnkRefTy.newTree(objectty)
  var root = newNimNode(nnkTypeSection).add(
    newNimNode(nnkTypeDef).add(
      ident(name),
      newEmptyNode(),
      objectty
    )
  )
  result = UnfinishedObjectTypeDef(root: root, insertion: insertion)

proc addObjectField*(objtypedef: UnfinishedObjectTypeDef, name: string, kind: NimNode) {.compileTime.} =
  ## Adds a field to an object definition created by newObjectTypeDef
  objtypedef.insertion.add(newIdentDefs(
    newNimNode(nnkPostfix).add(
      ident("*"),
      ident(name),
    ),
    kind,
    newEmptyNode(),
  ))

proc addObjectField*(objtypedef: UnfinishedObjectTypeDef, name: string, kind: string, isref: bool = false) {.compileTime.} =
  ## Adds a field to an object definition created by newObjectTypeDef
  if isref:
    addObjectField(objtypedef, name, nnkRefTy.newTree(ident(kind)))
  else:
    addObjectField(objtypedef, name, ident(kind))

proc newCaseStatement*(key: NimNode):UnfinishedCase =
  result = UnfinishedCase()
  result.root = nnkCaseStmt.newTree(key)

proc newCaseStatement*(key: string):UnfinishedCase =
  return newCaseStatement(ident(key))  

proc add*(n:var UnfinishedCase, opt: seq[NimNode], body: NimNode) =
  ## Adds a branch to an UnfinishedCase
  var branch = nnkOfBranch.newTree()
  for node in opt:
    branch.add(node)
  branch.add(body)
  n.cases.add(branch)

proc add*(n:var UnfinishedCase, opt:string, body: NimNode) =
  ## Adds a branch to an UnfinishedCase
  add(n, @[newStrLitNode(opt)], body)

proc add*(n:var UnfinishedCase, opt:int, body: NimNode) =
  ## Adds an integer branch to an UnfinishedCase
  add(n, @[newLit(opt)], body)

proc addElse*(n: var UnfinishedCase, body: NimNode) =
  ## Add an else: to an UnfinishedCase
  n.elsebody = body

proc isValid*(n:UnfinishedCase): bool =
  return n.cases.len > 0 or n.elsebody != nil

proc finalize*(n:UnfinishedCase): NimNode =
  if n.cases.len > 0:
    for branch in n.cases:
      n.root.add(branch)
    if n.elsebody != nil:
      n.root.add(nnkElse.newTree(n.elsebody))
    result = n.root
  else:
    result = n.elsebody

proc newIfStatement*():UnfinishedIf =
  result = UnfinishedIf()
  result.root = nnkIfStmt.newTree()

proc add*(n: var UnfinishedIf, cond: NimNode, body: NimNode) =
  add(n.root, nnkElifBranch.newTree(
    cond,
    body,
  ))

proc addElse*(n: var UnfinishedIf, body: NimNode) =
  ## Add an else: to an UnfinishedIf
  n.elsebody = body

proc isValid*(n:UnfinishedIf): bool =
  return n.root.len > 0 or n.elsebody != nil

proc finalize*(n:UnfinishedIf): NimNode =
  ## Finish an If statement
  result = n.root
  if n.root.len == 0:
    # This "if" is only an "else"
    result = n.elsebody
  elif n.elsebody != nil:
      result.add(nnkElse.newTree(n.elsebody))


proc nimRepr*(n:NimNode): string =
  case n.kind
  of nnkStmtList:
    var lines:seq[string]
    for child in n:
      lines.add(child.nimRepr)
    result = lines.join("\L")
  of nnkCommand:
    let name = n[0].nimRepr
    var args:seq[string]
    for i, child in n:
      if i == 0:
        continue
      args.add(child.nimRepr)
    echo n.lispRepr
    let arglist = args.join(", ")
    result = &"{name}({arglist})"
  of nnkIdent:
    result = n.strVal
  of nnkStrLit:
    result = "[" & n.strVal & "]"
  else:
    result = &"<unknown {n.kind} {n.lispRepr}>"
import macros

type
  InsertableTree = object
    root*: NimNode
    insertion*: NimNode
  
  UnfinishedCase = object
    root*: NimNode
    cases*: seq[NimNode]
    elsenode*: NimNode

proc replaceNodes*(ast: NimNode): NimNode =
  ## Replace NimIdent and NimSym by a fresh ident node
  ##
  ## Use with the results of ``quote do: ...`` to get
  ## ASTs without symbol resolution having been done already.
  proc inspect(node: NimNode): NimNode =
    case node.kind:
    of {nnkIdent, nnkSym}:
      return ident($node)
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

proc parentOf*(node: NimNode, name:string): NimNode =
  ## Recursively search for an ident node of the given name and return
  ## the parent of that node.
  var stack:seq[NimNode] = @[node]
  while stack.len > 0:
    var n = stack.pop()
    for child in n.children:
      if child.kind == nnkIdent and child.strVal == name:
        return n
      else:
        stack.add(child)
  error("node not found: " & name)

proc getInsertionPoint*(node: var NimNode, name:string): NimNode =
  ## Return the parent node of the ident node named `name`
  ## with the parent node emptied out, first.
  result = node.parentOf(name)
  result.del(n = result.len)

proc newObjectTypeDef*(name: string): InsertableTree {.compileTime.} =
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
  result = InsertableTree(root: root, insertion: insertion)

proc addObjectField*(objtypedef: InsertableTree, name: string, kind: NimNode) {.compileTime.} =
  ## Adds a field to an object definition created by newObjectTypeDef
  objtypedef.insertion.add(newIdentDefs(
    newNimNode(nnkPostfix).add(
      ident("*"),
      ident(name),
    ),
    kind,
    newEmptyNode(),
  ))

proc addObjectField*(objtypedef: InsertableTree, name: string, kind: string) {.compileTime.} =
  ## Adds a field to an object definition created by newObjectTypeDef
  addObjectField(objtypedef, name, ident(kind))

proc newCaseStatement*(key: string):UnfinishedCase =
  result = UnfinishedCase()
  result.root = nnkCaseStmt.newTree(
    ident(key),
  )

proc add*(n:var UnfinishedCase, opt: NimNode, body: NimNode) =
  ## Adds a branch to an UnfinishedCase
  var branch = nnkOfBranch.newTree()
  branch.add(opt)
  branch.add(body)
  n.cases.add(branch)

proc add*(n:var UnfinishedCase, opt:string, body: NimNode) =
  ## Adds a branch to an UnfinishedCase
  add(n, newStrLitNode(opt), body)

proc add*(n:var UnfinishedCase, opt:int, body: NimNode) =
  ## Adds an integer branch to an UnfinishedCase
  add(n, newLit(opt), body)

proc addElse*(n: var UnfinishedCase, body: NimNode) =
  ## Add an else: to an UnfinishedCase
  n.elsenode = body

proc finalize*(n:UnfinishedCase): NimNode =
  for branch in n.cases:
    n.root.add(branch)
  if n.elsenode != nil:
    n.root.add(nnkElse.newTree(n.elsenode))
  result = n.root

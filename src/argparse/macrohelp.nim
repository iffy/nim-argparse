import macros

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
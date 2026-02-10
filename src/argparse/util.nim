## Utilities used by multiple modules.
## 
## + Avoids circular dependencies.
## + Better module cohesion, all logic within more closely aligned to a purpose

import types
import std/[macros,options]

proc getProgNameAst*(b:Builder): NimNode {.compiletime.}=
  ## Get the program name for help text and completions
  ##
  ## if `b.name` == "": getAppFilename().extractFilename() else: `b.name`
  if b.name == "":
    result = newCall(newDotExpr(newCall("getAppFilename"), ident("extractFilename")))
  else:
    result = newLit(b.name)

proc parserIdent*(b: Builder): NimNode =
  ## Name of the parser type for this Builder
  # let name = if b.name == "": "Argparse" else: b.name
  ident("Parser" & b.symbol)
  
proc getRootBuilder*(b: Builder): Builder {.compiletime.} =
  ## Get the root builder for this builder
  var current = b
  while current.parent.isSome:
    current = current.parent.get()
  current
    

## Some module documentation.
##
import sequtils
import strutils
import algorithm
import macros
import strformat
import parseopt
import argparse/macrohelp

# export parseopt

type
  ComponentKind = enum
    Flag,
    Option,
    Argument,
  
  Component = object
    varname*: string
    help*: string
    case kind*: ComponentKind
    of Flag:
      shortflag*: string
      longflag*: string
    of Option:
      shortopt*: string
      longopt*: string
    of Argument:
      nargs*: int
  
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
  result.add("\L\L")

  # usage
  var usage_parts:seq[string]

  proc formatOption(flags:string, helptext:string, opt_width = 26, max_width = 100):string =
    result.add("  " & flags)
    if helptext != "":
      if flags.len > opt_width:
        result.add("\L")
        result.add("  ")
        result.add(" ".repeat(opt_width+1))
        result.add(helptext)
      else:
        result.add(" ".repeat(opt_width - flags.len))
        result.add(" ")
        result.add(helptext)

  var opts = ""
  var args = ""

  # Options and Arguments
  for comp in builder.components:
    case comp.kind
    of Flag:
      var flag_parts: seq[string]
      if comp.shortflag != "":
        flag_parts.add("-" & comp.shortflag)
      if comp.longflag != "":
        flag_parts.add("--" & comp.longflag)
      opts.add(formatOption(flag_parts.join(", "), comp.help))
      opts.add("\L")
    of Option:
      var flag_parts: seq[string]
      if comp.shortopt != "":
        flag_parts.add("-" & comp.shortopt)
      if comp.longopt != "":
        flag_parts.add("--" & comp.longopt)
      var flags = flag_parts.join(", ") & "=" & comp.varname.toUpper()
      opts.add(formatOption(flags, comp.help))
      opts.add("\L")
    of Argument:
      var leftside:string
      if comp.nargs == 1:
        leftside = comp.varname
      elif comp.nargs == -1:
        leftside = &"[{comp.varname} ...]"
      else:
        leftside = (&"{comp.varname} ").repeat(comp.nargs)
      usage_parts.add(leftside)
      args.add(formatOption(leftside, comp.help, opt_width=10))
      args.add("\L")
  
  if usage_parts.len > 0:
    result.add("Usage:\L")
    result.add("  ")
    result.add(builder.name & " ")
    if opts != "":
      result.add("[options] ")
    result.add(usage_parts.join(" "))
    result.add("\L\L")

  if args != "":
    result.add("Arguments:\L")
    result.add(args)
    result.add("\L")

  if opts != "":
    result.add("Options:\L")
    result.add(opts)
    result.add("\L")

proc genReturnType(builder: var Builder): NimNode {.compileTime.} =
  var objdef = newObjectTypeDef(builder.optsIdent.strVal)
  for comp in builder.components:
    case comp.kind
    of Flag:
      objdef.addObjectField(comp.varname, "bool")
    of Option:
      objdef.addObjectField(comp.varname, "string")
    of Argument:
      if comp.nargs == 1:
        objdef.addObjectField(comp.varname, "string")
      else:
        objdef.addObjectField(comp.varname, nnkBracketExpr.newTree(
          ident("seq"),
          ident("string"),
        ))
  result = objdef.root

proc handleShortOptions(builder: Builder): NimNode {.compileTime.} =
  var cs = newCaseStatement("key")
  cs.addElse(replaceNodes(quote do:
    echo "unknown flag: -" & key
  ))
  for comp in builder.components:
    case comp.kind
    of Argument:
      discard
    of Flag:
      if comp.shortflag != "":
        let varname = ident(comp.varname)
        cs.add(comp.shortflag, replaceNodes(quote do:
          result.`varname` = true
        ))
    of Option:
      if comp.shortopt != "":
        let varname = ident(comp.varname)
        cs.add(comp.shortopt, replaceNodes(quote do:
          result.`varname` = val
        ))
  result = cs.finalize()

proc handleLongOptions(builder: Builder): NimNode =
  var cs = newCaseStatement("key")
  cs.addElse(replaceNodes(quote do:
    echo "unknown flag: --" & key
  ))
  for comp in builder.components:
    case comp.kind
    of Argument:
      discard
    of Flag:
      if comp.longflag != "":
        let varname = ident(comp.varname)
        cs.add(comp.longflag, replaceNodes(quote do:
          result.`varname` = true
        ))
    of Option:
      if comp.longopt != "":
        let varname = ident(comp.varname)
        cs.add(comp.longopt, replaceNodes(quote do:
          result.`varname` = val
        ))
  result = cs.finalize()

proc popleft*[T](s: var seq[T]):T =
  result = s[0]
  s.delete(0, 0)

proc handleArguments(builder: Builder): NimNode =
  ## The result is used in the context defined by genParseProc
  result = newStmtList()
  var unlimited_taker:NimNode
  var fromend:seq[NimNode] # this will be added to the tree in reverse order
  for comp in builder.components:
    case comp.kind
    of Flag, Option:
      discard
    of Argument:
      let varname = ident(comp.varname)
      if comp.nargs == -1:
        # any number of args
        unlimited_taker = replaceNodes(quote do:
          result.`varname` = leftover
        )
      else:
        # specific number of args
        if unlimited_taker == nil:
          # before unlimited taker
          for i in 0..comp.nargs-1:
            result.add(replaceNodes(quote do:
              result.`varname`.add(leftover.popleft())
            ))
        else:
          # after unlimited taker
          for i in 0..comp.nargs-1:
            fromend.add(replaceNodes(quote do:
              result.`varname`.insert(leftover.pop(), 0)
            ))
  for node in reversed(fromend):
    result.add(node)
  if unlimited_taker != nil:
    result.add(unlimited_taker)



proc genParseProc(builder: var Builder): NimNode {.compileTime.} =
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()
  var rep = replaceNodes(quote do:
    proc parse(p:`ParserIdent`, input:string):`OptsIdent` =
      result = `OptsIdent`()
      var p = initOptParser(input)
      var leftover:seq[string]
      for kind, key, val in p.getopt():
        case kind
        of cmdEnd:
          discard
        of cmdShortOption:
          insertshort
        of cmdLongOption:
          insertlong
        of cmdArgument:
          leftover.add(key)
      block:
        insertargs
  )
  var shorts = rep.getInsertionPoint("insertshort")
  var longs = rep.getInsertionPoint("insertlong")
  var args = rep.getInsertionPoint("insertargs")
  shorts.add(handleShortOptions(builder))
  longs.add(handleLongOptions(builder))
  args.add(handleArguments(builder))
  result = rep

proc mkParser(name: string, content: proc()): NimNode {.compileTime.} =
  ## Where all the magic starts
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  let parserIdent = builder.parserIdent()
  
  # Generate help
  let helptext = builder.genHelp()

  # Create the parser return type
  result.add(builder.genReturnType())

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


proc flag*(opt1: string, opt2: string = "", help:string = "") {.compileTime.} =
  ## Add a boolean flag to the argument parser.  The boolean
  ## will be available on the parsed options object as the
  ## longest named flag.
  ##
  ## .. code-block:: nim
  ##   mkParser("Some Thing"):
  ##     flag("-n", "--dryrun", help="Don't actually run")
  var c = Component()
  c.kind = Flag
  c.help = help

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

proc option*(opt1: string, opt2: string = "", help:string="") =
  ## Add an option to the argument parser.  The longest
  ## named flag will be used as the name on the parsed
  ## result.
  ##
  ## .. code-block:: nim
  ##    var p = mkParser("Command"):
  ##      option("-a", "--apple", help="Name of apple")
  ##
  ##    assert p.parse("-a 5").apple == "5"
  var c = Component()
  c.kind = Option
  c.help = help

  if opt1.startsWith("--"):
    c.shortopt = opt2.stripHypens
    c.longopt = opt1.stripHypens
  else:
    c.shortopt = opt1.stripHypens
    c.longopt = opt2.stripHypens
  
  if c.longopt != "":
    c.varname = c.longopt.toUnderscores
  else:
    c.varname = c.shortopt.toUnderscores
  
  builderstack[^1].add(c)

proc arg*(varname: string, nargs=1, help:string="") =
  ## Add an argument to the argument parser.
  ##
  ## .. code-block:: nim
  ##    var p = mkParser("Command"):
  ##      arg("name", help="Name of apple")
  ##      arg("more", nargs=-1)
  ##
  ##    assert p.parse("cameo").name == "cameo"
  var c = Component()
  c.kind = Argument
  c.help = help
  c.varname = varname
  c.nargs = nargs
  builderstack[^1].add(c)

template newParser*(name: string, content: untyped): untyped =
  ## Entry point for making command-line parsers.
  ##
  ## .. code-block:: nim
  ##    var p = newParser("My program"):
  ##      flag("-a")
  ##    assert p.parse("-a").a == true
  macro tmpmkParser(): untyped =
    mkParser(name):
      content
  tmpmkParser()


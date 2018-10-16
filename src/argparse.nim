## Some module documentation.
##
import sequtils
import strutils
import algorithm
import macros
import os
import strformat
import parseopt
import argparse/macrohelp

export parseopt
export os

type
  ComponentKind = enum
    Flag,
    Option,
    Argument,
  
  Component = object
    varname*: string
    help*: string
    case kind*: ComponentKind
    of Flag, Option:
      shortflag*: string
      longflag*: string
    of Argument:
      nargs*: int
  
  Builder = object
    name*: string
    help*: string
    symbol*: string
    components*: seq[Component]
    children*: seq[Builder]
    run: proc()


var builderstack {.compileTime.} : seq[Builder] = @[]

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

proc add(builder: var Builder, child: Builder) {.compileTime.} =
  builder.children.add(child)

proc genHelp(builder: var Builder):string {.compileTime.} =
  ## Generate the usage/help text for the parser.
  result.add(builder.name)
  result.add("\L\L")

  # usage
  var usage_parts:seq[string]

  proc firstline(s:string):string =
    s.split("\L")[0]

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
  var commands = ""

  # Options and Arguments
  for comp in builder.components:
    case comp.kind
    of Flag:
      var flag_parts: seq[string]
      if comp.shortflag != "":
        flag_parts.add(comp.shortflag)
      if comp.longflag != "":
        flag_parts.add(comp.longflag)
      opts.add(formatOption(flag_parts.join(", "), comp.help))
      opts.add("\L")
    of Option:
      var flag_parts: seq[string]
      if comp.shortflag != "":
        flag_parts.add(comp.shortflag)
      if comp.longflag != "":
        flag_parts.add(comp.longflag)
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
  
  if builder.children.len > 0:
    usage_parts.add("COMMAND")
    for subbuilder in builder.children:
      var leftside = subbuilder.name
      commands.add(formatOption(leftside, subbuilder.help.firstline, opt_width=10))
      commands.add("\L")
  
  if usage_parts.len > 0:
    result.add("Usage:\L")
    result.add("  ")
    result.add(builder.name & " ")
    if opts != "":
      result.add("[options] ")
    result.add(usage_parts.join(" "))
    result.add("\L\L")

  if commands != "":
    result.add("Commands:\L")
    result.add(commands)
    result.add("\L")

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

proc handleOptions(builder: Builder): NimNode =
  # This is called within the context of genParseProcs
  #
  # argi  = index of current argument
  # input = seq[string] of all arguments
  # arg   = current string argument
  var cs = newCaseStatement("arg")
  cs.addElse(replaceNodes(quote do:
    echo "unknown option: " & arg
  ))
  for comp in builder.components:
    case comp.kind
    of Argument:
      discard
    of Flag, Option:
      var ofs:seq[NimNode] = @[]
      if comp.shortflag != "":
        ofs.add(newLit(comp.shortflag))
      if comp.longflag != "":
        ofs.add(newLit(comp.longflag))
      let varname = ident(comp.varname)
      if comp.kind == Flag:
        cs.add(ofs, replaceNodes(quote do:
          result.`varname` = true
        ))
      elif comp.kind == Option:
        cs.add(ofs, replaceNodes(quote do:
          inc(argi)
          result.`varname` = input[argi]
        ))
  result = cs.finalize()

proc popleft*[T](s: var seq[T]):T =
  result = s[0]
  s.delete(0, 0)

proc handleArguments(builder: Builder): tuple[handler:NimNode, flusher:NimNode] =
  ## The result is used in the context defined by genParseProcs
  ## This is called within the context of genParseProcs
  ##
  ## argi  = index of current argument
  ## input = seq[string] of all arguments
  ## arg   = current string argument
  ## unclaimed_args = seq of args not yet assigned to things.
  ## args_encountered = number of non-flag arguments encountered
  
  # run when an argument is encountered
  var handler = newStmtList()

  # run after all arguments have been processed
  var flusher = newStmtList()

  var unlimited_taker:NimNode
  var fromend:seq[NimNode] # this will be added to the tree in reverse order
  var arg_pointer = 0
  for comp in builder.components:
    case comp.kind
    of Flag, Option:
      discard
    of Argument:
      let varname = ident(comp.varname)
      if comp.nargs == -1:
        # any number of args
        unlimited_taker = replaceNodes(quote do:
          res.`varname` = unclaimed_args
        )
        let start = newLit(arg_pointer)
        handler.add(replaceNodes(quote do:
          if args_encountered >= `start`:
            unclaimed_args.add(arg)
        ))
      else:
        # specific number of args
        if unlimited_taker == nil:
          # before unlimited taker
          var start = newLit(arg_pointer)
          inc(arg_pointer, comp.nargs)
          var endval = newLit(arg_pointer)
          handler.add(replaceNodes(quote do:
            if args_encountered >= `start` and args_encountered < `endval`:
              result.`varname`.add(arg)
          ))
        else:
          # after unlimited taker
          for i in 0..comp.nargs-1:
            fromend.add(replaceNodes(quote do:
              res.`varname`.insert(unclaimed_args.pop(), 0)
            ))
  for node in reversed(fromend):
    flusher.add(node)
  if unlimited_taker != nil:
    flusher.add(unlimited_taker)
  
  result = (handler: handler, flusher: flusher)

proc genParseProcs(builder: var Builder): NimNode {.compileTime.} =
  result = newStmtList()
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()

  # parse(seq[string])
  var parse_seq_string = replaceNodes(quote do:
    proc parse(p:`ParserIdent`, orig_input: seq[string]):`OptsIdent` {.used.} =
      result = `OptsIdent`()
      var argi = 0
      var input = orig_input
      var unclaimed_args:seq[string]
      var args_encountered = 0
      proc flushUnclaimed(res:var `OptsIdent`) =
        block:
          HEYflush
      while argi < input.len:
        var arg = input[argi]
        if arg.startsWith("-"):
          if arg.find("=") > 1:
            var parts = arg.split({'='})
            input.insert(parts[1], argi+1)
            arg = parts[0]
          block:
            HEYoptions
        else:
          block:
            HEYarg
          inc(args_encountered)
        inc(argi)
      flushUnclaimed(result)
      # var leftover:seq[string]
      # for kind, key, val in p.getopt():
      #   case kind
      #   of cmdEnd:
      #     discard
      #   of cmdShortOption:
      #     insertshort
      #   of cmdLongOption:
      #     insertlong
      #   of cmdArgument:
      #     leftover.add(key)
      # block:
      #   insertargs
  )
  var opts = parse_seq_string.getInsertionPoint("HEYoptions")
  var args = parse_seq_string.getInsertionPoint("HEYarg")
  var flushUnclaimed = parse_seq_string.getInsertionPoint("HEYflush")
  var arghandlers = handleArguments(builder)
  opts.add(handleOptions(builder))
  args.add(arghandlers.handler)
  flushUnclaimed.add(arghandlers.flusher)
  result.add(parse_seq_string)

  when declared(commandLineParams):
    # parse()
    var parse_cli = replaceNodes(quote do:
      proc parse(p:`ParserIdent`):`OptsIdent` {.used.} =
        return parse(p, commandLineParams())
    )
    result.add(parse_cli)

proc genRunProc(builder: var Builder): NimNode {.compileTime.} =
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()
  result = replaceNodes(quote do:
    proc run(p:`ParserIdent`, orig_input:seq[string]) {.used.} =
      var input = orig_input
      echo "hi from run", input.repr
  )

proc mkParser(name: string, content: proc()): NimNode {.compileTime.} =
  ## Where all the magic starts
  echo "mkParser ", name
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  if builderstack.len > 0:
    builderstack[^1].add(builder)
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

  # Create the parse procs
  result.add(builder.genParseProcs())
  # Create the run proc
  result.add(builder.genRunProc())

  # Instantiate a parser and return an instance
  result.add(replaceNodes(quote do:
    var parser = `parserIdent`()
    parser.help = `helptext`
    parser
  ))

proc toUnderscores(s:string):string =
  s.replace('-','_').strip(chars={'_'})


proc flag*(opt1: string, opt2: string = "", help:string = "") {.compileTime.} =
  ## Add a boolean flag to the argument parser.  The boolean
  ## will be available on the parsed options object as the
  ## longest named flag.
  ##
  ## .. code-block:: nim
  ##   newParser("Some Thing"):
  ##     flag("-n", "--dryrun", help="Don't actually run")
  var c = Component()
  c.kind = Flag
  c.help = help

  if opt1.startsWith("--"):
    c.shortflag = opt2
    c.longflag = opt1
  else:
    c.shortflag = opt1
    c.longflag = opt2
  
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
  ##    var p = newParser("Command"):
  ##      option("-a", "--apple", help="Name of apple")
  ##
  ##    assert p.parse("-a 5").apple == "5"
  var c = Component()
  c.kind = Option
  c.help = help

  if opt1.startsWith("--"):
    c.shortflag = opt2
    c.longflag = opt1
  else:
    c.shortflag = opt1
    c.longflag = opt2
  
  if c.longflag != "":
    c.varname = c.longflag.toUnderscores
  else:
    c.varname = c.shortflag.toUnderscores
  
  builderstack[^1].add(c)

proc arg*(varname: string, nargs=1, help:string="") =
  ## Add an argument to the argument parser.
  ##
  ## .. code-block:: nim
  ##    var p = newParser("Command"):
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

proc help*(content: string) {.compileTime.} =
  ## Add help to a parser or subcommand.
  ##
  ## .. code-block:: nim
  ##    var p = newParser("Some Program"):
  ##      help("Some helpful description")
  ##      command "dostuff":
  ##        help("More helpful information")
  builderstack[^1].help = content

proc run*(content: proc()) {.compileTime.} =
  ## Define a handler for a command/subcommand.
  ##
  echo "in parser run def: " & content.repr
  builderstack[^1].run = content

proc command*(name: string, content: proc()) {.compileTime.} =
  ## Add a sub-command to the argument parser.
  ##
  hint("command getting evaluated: " & builderstack.len.intToStr)
  discard mkParser(name, content)
  hint("command parser made: " & builderstack.len.intToStr)

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


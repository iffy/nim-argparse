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
    node*: NimNode
    runProcBodies*: seq[NimNode]
  
  ParsingState* = object
    input*: seq[string]
    i*: int
    args_encountered*: int
    unclaimed*: seq[string]
    runProcs*: seq[proc()]
    nestlevel*: int

type
  ParseResult[T] = tuple[state: ParsingState, opts: T]



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

proc genHelp(builder: Builder):string {.compileTime.} =
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

proc genHelpProc(builder: Builder): NimNode {.compileTime.} =
  let ParserIdent = builder.parserIdent()
  let helptext = builder.genHelp()
  result = replaceNodes(quote do:
    proc help(p:`ParserIdent`):string {.used.} =
      result = `helptext`
  )

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

proc mkFlagHandler(builder: Builder): NimNode =
  ## This is called within the context of genParseProcs
  ##
  ## state = ParsingState
  ## result = options specific to the builder
  var cs = newCaseStatement("arg")
  cs.addElse(replaceNodes(quote do:
    echo "unknown option: " & state.current
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
          opts.`varname` = true
        ))
      elif comp.kind == Option:
        cs.add(ofs, replaceNodes(quote do:
          state.inc()
          opts.`varname` = state.current
        ))
  result = cs.finalize()

proc popleft*[T](s: var seq[T]):T =
  result = s[0]
  s.delete(0, 0)

proc mkArgHandler(builder: Builder): tuple[handler:NimNode, flusher:NimNode] =
  ## The result is used in the context defined by genParseProcs
  ## This is called within the context of genParseProcs
  ##
  ## state = ParsingState
  ## result = options specific to the builder

  ## run when a flush is required
  var doFlush = newStmtList()
  var fromEnd: seq[NimNode]

  ## run when an argument is encountered before a command is expected
  var onArgBeforeCommand = newIfStatement()

  ## run when an argument is encountered after a command is expected
  var onPossibleCommand = newCaseStatement("arg")
  
  ## run when an argument that's not a command nor an expected arg is encountered
  var unlimited_varname = ""
  var onNotCommand = replaceNodes(quote do:
    raise newException(CatchableError, "Unexpected argument: " & arg)
  )

  var arg_count = 0
  var minargs_before_command = 0

  for comp in builder.components:
    case comp.kind
    of Flag, Option:
      discard
    of Argument:
      let varname = ident(comp.varname)
      if comp.nargs == -1:
        # Unlimited taker
        unlimited_varname = comp.varname
        onNotCommand = replaceNodes(quote do:
          state.unclaimed.add(arg)
        )
        onPossibleCommand.addElse(replaceNodes(quote do:
          state.unclaimed.add(arg)
        ))
      else:
        # specific number of args
        minargs_before_command.inc(comp.nargs)
        if unlimited_varname == "":
          # before unlimited taker
          var startval = newLit(arg_count)
          inc(arg_count, comp.nargs)
          var endval = newLit(arg_count - 1)
          let condition = replaceNodes(quote do:
            state.args_encountered in `startval`..`endval`
          )
          let action = replaceNodes(quote do:
            opts.`varname`.add(arg)
          )
          onArgBeforeCommand.add(condition, action)
        else:
          # after unlimited taker
          onArgBeforeCommand.addElse(replaceNodes(quote do:
            state.unclaimed.add(arg)
          ))
          for i in 0..comp.nargs-1:
            fromEnd.add(replaceNodes(quote do:
              opts.`varname`.insert(state.unclaimed.pop(), 0)
            ))
  
  # define doFlush
  for node in reversed(fromEnd):
    doFlush.add(node)
  if unlimited_varname != "":
    let varname = ident(unlimited_varname)
    doFlush.add(replaceNodes(quote do:
      opts.`varname` = state.unclaimed
      state.unclaimed.setLen(0)
    ))
  
  # handle commands
  for command in builder.children:
    let ParserIdent = command.parserIdent()
    onPossibleCommand.add(command.name, replaceNodes(quote do:
      let subparser = `ParserIdent`()
      discard subparser.parse(state, alsorun)
    ))

  
  var mainIf = newIfStatement()
  if onArgBeforeCommand.isValid:
    let condition = replaceNodes(quote do:
      state.args_encountered < `minargs_before_command`
    )
    mainIf.add(condition, onArgBeforeCommand.finalize())

  if onPossibleCommand.isValid:
    mainIf.addElse(onPossibleCommand.finalize())
  
  var handler = newStmtList()
  if mainIf.isValid:
    handler = mainIf.finalize()
  result = (handler: handler, flusher: doFlush)

proc isdone*(state: var ParsingState):bool =
  state.i >= state.input.len

proc inc*(state: var ParsingState) =
  if not state.isdone:
    inc(state.i)

proc current*(state: ParsingState):string =
  ## Return the current argument to be processed
  state.input[state.i]

proc replace*(state: var ParsingState, val: string) =
  ## Replace the current argument with another one
  state.input[state.i] = val

proc insertArg*(state: var ParsingState, val: string) =
  ## Insert an argument after the current argument
  state.input.insert(val, state.i+1)

proc genParseProcs(builder: var Builder): NimNode {.compileTime.} =
  result = newStmtList()
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()

  # parse(seq[string])
  var parse_seq_string = replaceNodes(quote do:
    proc parse(p:`ParserIdent`, state:var ParsingState, alsorun:bool):`OptsIdent` {.used.} =
      state.nestlevel.inc()
      var opts = `OptsIdent`()
      block:
        HEYaddRunProc
      while not state.isdone:
        var arg = state.current
        if arg.startsWith("-"):
          if arg.find("=") > 1:
            var parts = arg.split({'='})
            state.replace(parts[0])
            state.insertArg(parts[1])
            arg = state.current
          block:
            HEYoptions
        else:
          block:
            HEYarg
          state.args_encountered.inc()
        state.inc()
      block:
        HEYflush
      if alsorun and state.nestlevel == 1:
        for p in state.runProcs:
          p()
      state.nestlevel.dec()
      return opts
    proc parse(p:`ParserIdent`, input: seq[string], alsorun:bool = false):`OptsIdent` {.used.} =
      var varinput = input
      var state = ParsingState(input: varinput)
      return parse(p, state, alsorun)
  )
  var opts = parse_seq_string.getInsertionPoint("HEYoptions")
  var args = parse_seq_string.getInsertionPoint("HEYarg")
  var flushUnclaimed = parse_seq_string.getInsertionPoint("HEYflush")
  var arghandlers = mkArgHandler(builder)
  flushUnclaimed.add(arghandlers.flusher)
  args.add(arghandlers.handler)
  opts.add(mkFlagHandler(builder))

  var addRunProc = parse_seq_string.getInsertionPoint("HEYaddRunProc")
  for p in builder.runProcBodies:
    addRunProc.add(quote do:
      state.runProcs.add(proc() =
        `p`
      )
    )

  result.add(parse_seq_string)

  when declared(commandLineParams):
    # parse()
    var parse_cli = replaceNodes(quote do:
      proc parse(p:`ParserIdent`, alsorun:bool = false):`OptsIdent` {.used.} =
        return parse(p, commandLineParams(), alsorun)
    )
    result.add(parse_cli)

proc genRunProc(builder: var Builder): NimNode {.compileTime.} =
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()
  result = replaceNodes(quote do:
    proc run(p:`ParserIdent`, orig_input:seq[string]) {.used.} =
      discard p.parse(orig_input, alsorun=true)
  )

proc mkParser(name: string, content: proc(), instantiate:bool = true): NimNode {.compileTime.} =
  ## Where all the magic starts
  result = newStmtList()
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  builder.node = result
  if builderstack.len > 0:
    builderstack[^1].add(builder)

  # Create the parser return type
  result.add(builder.genReturnType())

  # Create the parser type
  let parserIdent = builder.parserIdent()
  result.add(replaceNodes(quote do:
    type
      `parserIdent` = object
  ))

  # Add child definitions
  for child in builder.children:
    result.add(child.node)

  # Create the help proc
  result.add(builder.genHelpProc())
  # Create the parse procs
  result.add(builder.genParseProcs())
  # Create the run proc
  result.add(builder.genRunProc())

  # Instantiate a parser and return an instance
  if instantiate:
    result.add(replaceNodes(quote do:
      var parser = `parserIdent`()
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

proc performRun(body: NimNode):untyped {.compileTime.} =
  ## Define a handler for a command/subcommand.
  ##
  builderstack[^1].runProcBodies.add(body)

template run*(content: untyped): untyped =
  performRun(replaceNodes(quote(content)))

proc command*(name: string, content: proc()) {.compileTime.} =
  ## Add a sub-command to the argument parser.
  ##
  discard mkParser(name, content, instantiate = false)

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


## argparse is an explicit, strongly-typed command line argument
## parser.
##
## Because this module makes heavy use of macros, there are several exported procs, types and templates that aren't intended for direct use but which are exported because the macros make use of them.  The documentation and examples should make the distinction clear.
##
## Use ``newParser`` to create a parser.  Within the body
## of the parser use the following:
##
## - ``flag`` - for boolean flags (e.g. ``--dryrun``)
## - ``option`` - for options which have arguments (e.g. ``--output foo``)
## - ``arg`` - for positional arguments (e.g. ``file1 file2``)
## - ``command`` - for sub commands
## - ``run`` - to define code to run when the parser is used in run mode rather than parse mode.  See the documentation for more information.
## - ``help`` - to define a help string for the parser/subcommand
## - ``nohelpflag`` - to disable the automatic `-h/--help` flag.  When using ``parse()``, ``.help`` will be a boolean flag.
##
## The specials variables ``opts`` and ``opts.parentOpts`` are available within ``run`` blocks.
##
## If ``Parser.parse()`` and ``Parser.run()`` are called without arguments, they use the arguments from the command line.

runnableExamples:
  var p = newParser("My Program"):
    help("A description of this program")
    flag("-n", "--dryrun")
    option("-o", "--output", help="Write output to this file", default="somewhere.txt")
    option("-k", "--kind", choices = @["fruit", "vegetable"])
    arg("input")
  
  let opts = p.parse(@["-n", "--output", "another.txt", "cranberry"])
  assert opts.dryrun == true
  assert opts.output == "another.txt"
  assert opts.input == "cranberry"

runnableExamples:
  var res:string
  var p = newParser("Something"):
    flag("-n", "--dryrun")
    command("ls"):
      run:
        res = "did ls"
    command("run"):
      option("-c", "--command")
      run:
        if opts.parentOpts.dryrun:
          res = "would have run: " & opts.command
        else:
          res = "ran " & opts.command
  
  p.run(@["-n", "run", "--command", "something"])
  assert res == "would have run: something"
  

import sequtils
import strutils
import algorithm
import streams
import macros
import os
import strformat
import parseopt
import tables
import argparse/macrohelp

export parseopt
export os
export strutils
export macros
export streams

type
  ComponentKind = enum
    Flag,
    Option,
    Argument,
  
  Component = object
    varname*: string
    help*: string
    default*: string
    env*: string
    choices*: seq[string]
    case kind*: ComponentKind
    of Flag, Option:
      shortflag*: string
      longflag*: string
      multiple*: bool
    of Argument:
      nargs*: int
  
  Builder = ref BuilderObj
  BuilderObj {.acyclic.} = object
    name*: string
    help*: string
    nohelpflag*: bool
    symbol*: string
    components*: seq[Component]
    parent*: Builder
    alltypes*: UnfinishedObjectTypeDef
    children*: seq[Builder]
    typenode*: NimNode
    bodynode*: NimNode
    runProcBodies*: seq[NimNode]
    group*: string

  ParsingState* = ref object
    input*: seq[string]
    i*: int
    args_encountered*: int
    switches_seen*: seq[string]
    unclaimed*: seq[string]
    runProcs*: seq[proc()]
  
  UsageError* = object of CatchableError
  ShortCircuit* = object of CatchableError

type
  ParseResult[T] = tuple[state: ParsingState, opts: T]

var ARGPARSE_STDOUT* = newFileStream(stdout)

template throwUsageError*(message:string) =
  ## INTERNAL
  raise newException(UsageError, message)

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

  if builder.help != "":
    result.add(builder.help)
    result.add("\L\L")

  # usage
  var usage_parts:seq[string]

  proc firstline(s:string):string =
    s.split("\L")[0]

  proc formatOption(flags:string, helptext:string, defaultval:string = "", envvar:string = "", choices:seq[string] = @[], opt_width = 26, max_width = 100):string =
    result.add("  " & flags)
    var helptext = helptext
    if choices.len > 0:
      helptext.add(" Possible values: [" & choices.join(", ") & "]")
    if defaultval != "":
      helptext.add(&" (default: {defaultval})")
    if envvar != "":
      helptext.add(&" (env: {envvar})")
    helptext = helptext.strip()
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
      opts.add(formatOption(flags, comp.help, defaultval = comp.default, envvar = comp.env, choices = comp.choices))
      opts.add("\L")
    of Argument:
      var leftside:string
      if comp.nargs == 1:
        leftside = comp.varname
        if comp.default != "":
          leftside = &"[{comp.varname}]"
      elif comp.nargs == -1:
        leftside = &"[{comp.varname} ...]"
      else:
        leftside = (&"{comp.varname} ").repeat(comp.nargs)
      usage_parts.add(leftside)
      args.add(formatOption(leftside, comp.help, defaultval = comp.default, envvar = comp.env, opt_width=16))
      args.add("\L")
  
  var commands = newTable[string,string](2)

  if builder.children.len > 0:
    usage_parts.add("COMMAND")
    for subbuilder in builder.children:
      var leftside = subbuilder.name
      let group = subbuilder.group
      if not commands.hasKey(group):
        commands[group] = ""
      let indent = if group == "": "" else: "  "
      commands[group].add(indent & formatOption(leftside, subbuilder.help.firstline, opt_width=16))
      commands[group].add("\L")
  
  if usage_parts.len > 0 or opts != "":
    result.add("Usage:\L")
    result.add("  ")
    result.add(builder.name & " ")
    if opts != "":
      result.add("[options] ")
    result.add(usage_parts.join(" "))
    result.add("\L\L")

  if commands.len == 1:
    let key = toSeq(commands.keys())[0]
    result.add("Commands:\L\L")
    result.add(commands[key])
    result.add("\L")
  elif commands.len > 0:
    result.add("Commands:\L\L")
    for key in commands.keys():
      result.add("  " & key & ":\L\L")
      result.add(commands[key])
      result.add("\L")

  if args != "":
    result.add("Arguments:\L")
    result.add(args)
    result.add("\L")

  if opts != "":
    result.add("Options:\L")
    result.add(opts)
    result.add("\L")

  result.setLen(result.high) # equivalent to new Nim .stripLineEnd

proc genHelpProc(builder: Builder): NimNode {.compileTime.} =
  let ParserIdent = builder.parserIdent()
  let helptext = builder.genHelp()
  result = replaceNodes(quote do:
    proc help(p:`ParserIdent`):string {.used.} =
      result = `helptext`
  )

proc genReturnType(builder: var Builder): NimNode {.compileTime.} =
  ## Generate a node to describe the return type for a given Builder
  var objdef = newObjectTypeDef(builder.optsIdent.strVal)
  if builder.parent != nil:
    # Add the parent Opts type to this one
    objdef.addObjectField("parentOpts", builder.parent.optsIdent())

  for comp in builder.components:
    case comp.kind
    of Flag:
      if comp.multiple:
        objdef.addObjectField(comp.varname, "int")
      else:
        objdef.addObjectField(comp.varname, "bool")
    of Option:
      if comp.multiple:
        objdef.addObjectField(comp.varname, nnkBracketExpr.newTree(
          ident("seq"),
          ident("string"),
        ))
      else:
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
    throwUsageError("unknown option: " & state.current)
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
      let varname_string = newStrLitNode(comp.varname)
      if comp.kind == Flag:
        if comp.varname == "help":
          cs.add(ofs, replaceNodes(quote do:
            opts.help = true
            output.write(p.help)
            raise newException(ShortCircuit, "-h/--help")
          ))
        else:
          if comp.multiple:
            cs.add(ofs, replaceNodes(quote do:
              opts.`varname`.inc()
            ))
          else:
            cs.add(ofs, replaceNodes(quote do:
              opts.`varname` = true
            ))
      elif comp.kind == Option:
        if comp.choices.len > 0:
          # Restrict value to set of choices
          let choices = comp.choices
          if comp.multiple:
            cs.add(ofs, replaceNodes(quote do:
              state.inc()
              if state.current in `choices`:
                opts.`varname`.add(state.current)
              else:
                throwUsageError("Unacceptable value: " & state.current)
            ))
          else:
            cs.add(ofs, replaceNodes(quote do:
              state.inc()
              if `varname_string` in state.switches_seen:
                throwUsageError("Value for --" & `varname_string` & " already given: " & $opts.`varname`)
              if state.current in `choices`:
                opts.`varname` = state.current
                state.switches_seen.add(`varname_string`)
              else:
                throwUsageError("Unacceptable value: " & state.current)
            ))
        else:
          # Open-ended values accepted
          if comp.multiple:
            cs.add(ofs, replaceNodes(quote do:
              state.inc()
              opts.`varname`.add(state.current)
            ))
          else:
            cs.add(ofs, replaceNodes(quote do:
              state.inc()
              if `varname_string` in state.switches_seen:
                throwUsageError("Value for --" & `varname_string` & " already given: " & $opts.`varname`)
              opts.`varname` = state.current
              state.switches_seen.add(`varname_string`)
            ))
  result = cs.finalize()

proc mkDefaultSetter(builder: Builder): NimNode =
  ## The result is used in the context defined by genParseProcs
  ## This is called within the context of genParseProcs
  ##
  ## state = ParsingState
  ## opts  = options specific to the builder
  result = newStmtList()
  for comp in builder.components:
    let varname = ident(comp.varname)
    let defaultval = newLit(comp.default)
    let envvar = newLit(comp.env)
    case comp.kind
    of Option, Argument:
      if comp.env != "":
        result.add(replaceNodes(quote do:
          opts.`varname` = getEnv(`envvar`, `defaultval`)
        ))
      elif comp.default != "":
        result.add(replaceNodes(quote do:
          opts.`varname` = `defaultval`
        ))
    else:
      discard

proc popleft*[T](s: var seq[T]):T =
  ## INTERNAL: pop from the front of a seq
  result = s[0]
  s.delete(0, 0)

proc mkArgHandler(builder: Builder): tuple[handler:NimNode, flusher:NimNode, minargs:int] =
  ## The result is used in the context defined by genParseProcs
  ## This is called within the context of genParseProcs
  ##
  ## state = ParsingState
  ## opts  = options specific to the builder

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
  var minargs = 0

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
        if comp.default == "":
          minargs.inc(comp.nargs)
        if unlimited_varname == "":
          # before unlimited taker
          var startval = newLit(arg_count)
          inc(arg_count, comp.nargs)
          var endval = newLit(arg_count - 1)
          let condition = replaceNodes(quote do:
            state.args_encountered in `startval`..`endval`
          )
          var action = if comp.nargs == 1:
            replaceNodes(quote do:
              opts.`varname` = arg
            )
          else:
            replaceNodes(quote do:
              opts.`varname`.add(arg)
            )
          onArgBeforeCommand.add(condition, action)
        else:
          # after unlimited taker
          onArgBeforeCommand.addElse(replaceNodes(quote do:
            state.unclaimed.add(arg)
          ))
          for i in 0..comp.nargs-1:
            if comp.default == "":
              fromEnd.add(replaceNodes(quote do:
                opts.`varname`.insert(state.unclaimed.pop(), 0)
              ))
            else:
              # argument has a default
              fromEnd.add(
                if comp.nargs == 1:
                  replaceNodes(quote do:
                    if state.unclaimed.len > 0:
                      opts.`varname` = state.unclaimed.pop()
                  )
                else:
                  replaceNodes(quote do:
                    if state.unclaimed.len > 0:
                      opts.`varname`.insert(state.unclaimed.pop(), 0)
                  )
              )
  
  # define doFlush
  for node in reversed(fromEnd):
    doFlush.add(node)
  if unlimited_varname != "":
    # unlimited taker will take the rest
    let varname = ident(unlimited_varname)
    doFlush.add(replaceNodes(quote do:
      opts.`varname` = state.unclaimed
      state.unclaimed.setLen(0)
    ))
  
  # handle commands
  for command in builder.children:
    let ParserIdent = command.parserIdent()
    onPossibleCommand.add(command.name, replaceNodes(quote do:
      state.inc()
      let subparser = `ParserIdent`()
      var substate = ParsingState(
        input: state.input,
        i: state.i,
        args_encountered: state.args_encountered,
        unclaimed: state.unclaimed,
        runProcs: state.runProcs,
      )
      discard subparser.parse(substate, alsorun, output, opts)
      state.i = substate.i
      state.args_encountered = substate.args_encountered
      state.unclaimed = substate.unclaimed
      state.runProcs = substate.runProcs
    ))
  if builder.children.len > 0:
    onPossibleCommand.addElse(replaceNodes(quote do:
      state.unclaimed.add(arg)
    ))

  
  var mainIf = newIfStatement()
  if onArgBeforeCommand.isValid:
    let condition = replaceNodes(quote do:
      state.args_encountered < `minargs_before_command`
    )
    mainIf.add(condition, onArgBeforeCommand.finalize())

  if onPossibleCommand.isValid:
    mainIf.addElse(onPossibleCommand.finalize())
  else:
    mainIf.addElse(replaceNodes(quote do:
      state.unclaimed.add(arg)
    ))
  
  var handler = newStmtList()
  if mainIf.isValid:
    handler.add(mainIf.finalize())

  result = (handler: handler, flusher: doFlush, minargs: minargs)

proc isdone*(state: var ParsingState):bool =
  ## INTERNAL: true if the parser is done
  state.i >= state.input.len

proc inc*(state: var ParsingState) =
  ## INTERNAL: move to the next token
  if not state.isdone:
    inc(state.i)

proc subState*(state: var ParsingState): ParsingState =
  ## INTERNAL: Generate state for subparser
  new(result)
  result.input = state.input
  result.i = state.i
  result.args_encountered = state.args_encountered
  result.unclaimed = state.unclaimed
  result.runProcs = state.runProcs

proc current*(state: ParsingState):string =
  ## INTERNAL: Return the current argument to be processed
  state.input[state.i]

proc replace*(state: var ParsingState, val: string) =
  ## INTERNAL: Replace the current argument with another one
  state.input[state.i] = val

proc insertArg*(state: var ParsingState, val: string) =
  ## INTERNAL: Insert an argument after the current argument
  state.input.insert(val, state.i+1)

proc genParseProcs(builder: var Builder): NimNode {.compileTime.} =
  result = newStmtList()
  let OptsIdent = builder.optsIdent()
  let ParserIdent = builder.parserIdent()

  # parse(seq[string])
  var parse_seq_string = replaceNodes(quote do:
    proc parse(p:`ParserIdent`, state:var ParsingState, alsorun:bool, output:Stream, EXTRA):`OptsIdent` {.used.} =
      var opts = `OptsIdent`()
      HEYparentOpts
      HEYsetdefaults
      HEYaddRunProc
      try:
        while not state.isdone:
          var arg = state.current
          if arg.startsWith("-"):
            if arg.find("=") > 1:
              var parts = arg.split({'='})
              state.replace(parts[0])
              state.insertArg(parts[1])
              arg = state.current
            HEYoptions
          else:
            HEYarg
            state.args_encountered.inc()
          state.inc()
        HEYflush
        if state.unclaimed.len > 0:
          throwUsageError("Unknown arguments: " & $state.unclaimed)
        let minargs = HEYminargs
        if state.args_encountered < minargs:
          throwUsageError("Expected " & $minargs & " args but only found " & $state.args_encountered)
      except ShortCircuit:
        if alsorun:
          raise
      HEYrun
      return opts
  )

  var extra_args = parse_seq_string.parentOf("EXTRA")
  if builder.parent != nil:
    # Add an parentOpts as an extra argument for this parse proc
    extra_args.parent.del(0, 3)
    extra_args.parent.add(ident("parentOpts"))
    extra_args.parent.add(builder.parent.optsIdent)
    extra_args.parent.add(newEmptyNode())
  else:
    discard parse_seq_string.parentOf(extra_args.parent).clear()
  var opts = parse_seq_string.getInsertionPoint("HEYoptions")
  var args = parse_seq_string.getInsertionPoint("HEYarg")
  var flushUnclaimed = parse_seq_string.getInsertionPoint("HEYflush")
  var runsection = parse_seq_string.getInsertionPoint("HEYrun")
  parse_seq_string.getInsertionPoint("HEYsetdefaults").replace(builder.mkDefaultSetter())
  
  var arghandlers = mkArgHandler(builder)
  flushUnclaimed.replace(arghandlers.flusher)
  args.replace(arghandlers.handler)
  opts.replace(mkFlagHandler(builder))
  let minargs = arghandlers.minargs
  parse_seq_string.getInsertionPoint("HEYminargs").replace(replaceNodes(quote do:
    `minargs`
  ))


  let parentOptsProc = parse_seq_string.getInsertionPoint("HEYparentOpts")
  if builder.parent != nil:
    # Subcommand
    let ParentOptsIdent = builder.parent.optsIdent()
    parentOptsProc.replace(
      replaceNodes(quote do:
        opts.parentOpts = parentOpts
      )
    )
    discard runsection.clear()
  else:
    # Top-most parser
    discard parentOptsProc.clear()
    runsection.replace(
      replaceNodes(quote do:
        if alsorun:
          for p in state.runProcs:
            p()
      )
    )


  var addRunProcs = newStmtList()
  for p in builder.runProcBodies:
    addRunProcs.add(quote do:
      state.runProcs.add(proc() =
        `p`
      )
    )
  parse_seq_string.getInsertionPoint("HEYaddRunProc").replace(addRunProcs)

  result.add(parse_seq_string)

  if builder.parent == nil:
    # Add a convenience proc for parsing seq[string]
    result.add(replaceNodes(quote do:
      proc parse(p:`ParserIdent`, input: seq[string], alsorun:bool = false, output:Stream = ARGPARSE_STDOUT):`OptsIdent` {.used.} =
        var varinput = input
        var state = ParsingState(input: varinput)
        return parse(p, state, alsorun, output)
    ))
    when declared(commandLineParams):
      # parse() convenience method with no args
      var parse_cli = replaceNodes(quote do:
        proc parse(p:`ParserIdent`, alsorun:bool = false, output:Stream = ARGPARSE_STDOUT):`OptsIdent` {.used.} =
          return parse(p, commandLineParams(), alsorun, output)
      )
      result.add(parse_cli)

proc genRunProc(builder: var Builder): NimNode {.compileTime.} =
  let ParserIdent = builder.parserIdent()
  result = newStmtList()
  if builder.parent == nil:
    result.add(replaceNodes(quote do:
      proc run(p:`ParserIdent`, orig_input:seq[string], quitOnHelp:bool = true, output:Stream = ARGPARSE_STDOUT) {.used.} =
        try:
          discard p.parse(orig_input, alsorun=true, output = output)
        except ShortCircuit:
          if quitOnHelp:
            quit(0)
    ))
    when declared(commandLineParams):
      # run() convenience method with no args.
      result.add(replaceNodes(quote do:
        proc run(p:`ParserIdent`, quitOnHelp:bool = true) {.used.} =
          p.run(commandLineParams(), quitOnHelp)
      ))

proc mkParser(name: string, content: proc(), instantiate:bool = true, group:string = ""): tuple[types: NimNode, body:NimNode] {.compileTime.} =
  ## Where all the magic starts
  builderstack.add(newBuilder(name))
  content()

  var builder = builderstack.pop()
  builder.typenode = newStmtList()
  builder.bodynode = newStmtList()
  builder.group = group
  result = (types: builder.typenode, body: builder.bodynode)

  # -h/--help nohelpflag
  if not builder.nohelpflag:
    var helpflag = Component()
    helpflag.kind = Flag
    helpflag.help = "Show this help"
    helpflag.shortflag = "-h"
    helpflag.longflag = "--help"
    helpflag.varname = "help"
    builder.components.add(helpflag)

  if builderstack.len > 0:
    # subcommand
    builderstack[^1].add(builder)
    builder.parent = builderstack[^1]

  # Create the parser return type
  builder.typenode.add(builder.genReturnType())

  # Create the parser type
  let parserIdent = builder.parserIdent()
  builder.typenode.add(replaceNodes(quote do:
    type
      `parserIdent` = object
  ))

  # Add child definitions
  for child in builder.children:
    builder.typenode.add(child.typenode)
    builder.bodynode.add(child.bodynode)

  # Create the help proc
  builder.bodynode.add(builder.genHelpProc())
  # Create the parse procs
  builder.bodynode.add(builder.genParseProcs())
  # Create the run proc
  builder.bodynode.add(builder.genRunProc())

  # Instantiate a parser and return an instance
  if instantiate:
    builder.bodynode.add(replaceNodes(quote do:
      var parser = `parserIdent`()
      parser
    ))

proc toUnderscores(s:string):string =
  s.replace('-','_').strip(chars={'_'})


proc flag*(opt1: string, opt2: string = "", multiple = false, help:string = "") {.compileTime.} =
  ## Add a boolean flag to the argument parser.  The boolean
  ## will be available on the parsed options object as the
  ## longest named flag.
  ##
  ## If ``multiple`` is true then the flag can be specified multiple
  ## times and the datatype will be an int.
  runnableExamples:
    var p = newParser("Some Thing"):
      flag("-n", "--dryrun", help="Don't actually run")
  var c = Component()
  c.kind = Flag
  c.help = help
  c.multiple = multiple

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

proc option*(opt1: string, opt2: string = "", multiple = false, help:string="", default:string="", env:string="", choices:seq[string] = @[]) =
  ## Add an option to the argument parser.  The longest
  ## named flag will be used as the name on the parsed
  ## result.
  ##
  ## Set ``multiple`` to true to accept multiple options.
  ##
  ## Set ``default`` to the default string value.
  ##
  ## Set ``env`` to an environment variable name to use as the default value
  ## 
  ## Set ``choices`` to restrict the possible choices.
  ##
  runnableExamples:
    var p = newParser("Command"):
      option("-a", "--apple", help="Name of apple")
    assert p.parse(@["-a", "5"]).apple == "5"

  var c = Component()
  c.kind = Option
  c.help = help
  c.default = default
  c.env = env
  c.choices = choices
  c.multiple = multiple

  if multiple:
    assert default == "", "You may not specify a default for option(..., multiple=true)"

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

proc arg*(varname: string, nargs=1, help:string="", default:string="", env:string="") =
  ## Add an argument to the argument parser.
  ##
  ## Set ``default`` to the default string value.
  ##
  ## Set ``env`` to an environment variable name to use as the default value
  ##
  runnableExamples:
    var p = newParser("Command"):
      arg("name", help = "Name of apple")
      arg("more", nargs = -1)
    assert p.parse(@["cameo"]).name == "cameo"

  var c = Component()
  c.kind = Argument
  c.help = help
  c.varname = varname
  c.nargs = nargs
  c.default = default
  c.env = env
  builderstack[^1].add(c)

proc help*(content: string) {.compileTime.} =
  ## Add help to a parser or subcommand.
  ##
  runnableExamples:
    var p = newParser("Some Program"):
      help("Some helpful description")
      command("dostuff"):
        help("More helpful information")
    echo p.help
  builderstack[^1].help = content

proc nohelpflag*() {.compileTime.} =
  ## Disable the -h/--help flag that is usually added.
  runnableExamples:
    var p = newParser("Some Thing"):
      nohelpflag()
  builderstack[^1].nohelpflag = true

proc performRun(body: NimNode) {.compileTime.} =
  ## Define a handler for a command/subcommand.
  ##
  builderstack[^1].runProcBodies.add(body)

template run*(content: untyped): untyped =
  ## Specify code that should run when this command/sub-command is reached.
  runnableExamples:
    var p = newParser("Some Program"):
      command("dostuff"):
        run:
          echo "Actually do stuff"

    p.run(@["dostuff"])

  performRun(replaceNodes(quote(content)))

proc command*(name: string, content: proc(), group:string = "") {.compileTime.} =
  ## Add a sub-command to the argument parser.
  ##
  ## group is an optional string used to group commands in help output
  runnableExamples:
    var p = newParser("Some Program"):
      command("dostuff"):
        run:
          echo "Actually do stuff"
    p.run(@["dostuff"])

  discard mkParser(name, content, instantiate = false, group = group)

proc command*(name: string, group: string, content: proc()) {.compileTime.} =
  command(name, content, group)

template newParser*(name: string, content: untyped): untyped =
  ## Entry point for making command-line parsers.
  ##
  runnableExamples:
    var p = newParser("My program"):
      flag("-a")
    assert p.parse(@["-a"]).a == true

  macro tmpmkParser(): untyped =
    var res = mkParser(name):
      content
    newStmtList(
      res.types,
      res.body,
    )
  tmpmkParser()


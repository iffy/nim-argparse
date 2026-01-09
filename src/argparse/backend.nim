import algorithm; export algorithm
import macros
import options; export options
import sequtils; export sequtils
import streams; export streams
import strformat
import strutils; export strutils
import tables
import os; export os

import ./macrohelp
import ./filler

type
  UsageError* = object of ValueError
  ShortCircuit* = object of CatchableError
    flag*: string
    help*: string

  ComponentKind* = enum
    ArgFlag
    ArgOption
    ArgArgument

  Component* = object
    varname*: string
    hidden*: bool
    help*: string
    env*: string
    case kind*: ComponentKind
    of ArgFlag:
      flagShort*: string
      flagLong*: string
      flagMultiple*: bool
      shortCircuit*: bool
    of ArgOption:
      optShort*: string
      optLong*: string
      optMultiple*: bool
      optDefault*: Option[string]
      optChoices*: seq[string]
      optRequired*: bool
    of ArgArgument:
      nargs*: int
      argDefault*: Option[string]

  Builder* = ref BuilderObj
  BuilderObj* {.acyclic.} = object
    ## A compile-time object used to accumulate parser options
    ## before building the parser
    name*: string
      ## Command name for subcommand parsers, or program name for
      ## the parent parser.
    symbol*: string
      ## Unique tag to apply to Parser and Option types to avoid
      ## conflicts.  By default, this is generated with Nim's
      ## gensym algorithm.
    components*: seq[Component]
    help*: string
    groupName*: string
    children*: seq[Builder]
    parent*: Option[Builder]
    runProcBodies*: seq[NimNode]
  
  ParseState* = object
    tokens*: seq[string]
    cursor*: int
    extra*: seq[string]
      ## tokens that weren't parsed
    done*: bool
    token*: Option[string]
      ## The current unprocessed token
    key*: Option[string]
      ## The current key (possibly the head of a 'key=value' token)
    value*: Option[string]
      ## The current value (possibly the tail of a 'key=value' token)
    valuePartOfToken*: bool
      ## true if the value is part of the current token (e.g. 'key=value')
    runProcs*: seq[proc()]
      ## Procs to be run at the end of parsing

template doUsageAssert*(condition: bool, msg: string): untyped =
  ## Raise a UsageError if condition is false
  if not (`condition`):
    raise UsageError.newException(`msg`)

var ARGPARSE_STDOUT* = newFileStream(stdout)
var builderStack* {.compileTime.} = newSeq[Builder]()

proc toVarname*(x: string): string =
  ## Convert x to something suitable as a Nim identifier
  ## Replaces - with _ for instance
  x.replace("-", "_").strip(chars={'_'})

#--------------------------------------------------------------
# ParseState
#--------------------------------------------------------------

proc `$`*(state: ref ParseState): string {.inline.} = $(state[])

proc advance(state: ref ParseState, amount: int, skip = false) =
  ## Advance the parse by `amount` tokens
  ## 
  ## If `skip` is given, add the passed-over tokens to `extra`
  for i in 0..<amount:
    if state.cursor >= state.tokens.len:
      continue
    if skip:
      state.extra.add(state.tokens[state.cursor])
    state.cursor.inc()
  if state.cursor >= state.tokens.len:
    state.done = true
    state.token = none[string]()
    state.key = none[string]()
    state.value = none[string]()
    state.valuePartOfToken = false
  else:
    let token = state.tokens[state.cursor]
    state.token = some(token)
    if token.startsWith("-") and '=' in token:
      let parts = token.split("=", 1)
      state.key = some(parts[0])
      state.value = some(parts[1])
      state.valuePartOfToken = true
    else:
      state.key = some(token)
      state.valuePartOfToken = false
      if (state.cursor + 1) < state.tokens.len:
        state.value = some(state.tokens[state.cursor + 1])
      else:
        state.value = none[string]()

proc newParseState*(args: openArray[string]): ref ParseState =
  new(result)
  result.tokens = toSeq(args)
  result.extra = newSeq[string]()
  result.cursor = -1
  result.advance(1)

proc consume*(state: ref ParseState, thing: ComponentKind) =
  ## Advance the parser, marking some tokens as consumed.
  case thing
  of ArgFlag:
    state.advance(1)
  of ArgOption:
    state.advance(if state.valuePartOfToken: 1 else: 2)
  of ArgArgument:
    state.advance(1)

proc skip*(state: ref ParseState) {.inline.} =
  state.advance(1, skip = true)

#--------------------------------------------------------------
# General
#--------------------------------------------------------------

proc safeIdentStr(x: string): string =
  ## Remove components of a string that make it unsuitable as a Nim identifier
  for c in x:
    case c
    of '_':
      if result.len >= 1 and result[result.len-1] != '_':
        result.add c
    of 'A'..'Z', 'a'..'z', '\x80'..'\xff':
      result.add c
    of '0'..'9':
      if result.len >= 1:
        result.add c
    else:
      discard
  result.strip(chars = {'_'})

proc popleft*[T](s: var seq[T]):T =
  ## Pop from the front of a seq
  result = s[0]
  when (NimMajor, NimMinor, NimPatch) >= (1, 6, 0):
    s.delete(0..0)
  else:
    s.delete(0, 0)

proc popright*[T](s: var seq[T], n = 0): T =
  ## Pop the nth item from the end of a seq
  let idx = s.len - n - 1
  result = s[idx]
  when (NimMajor, NimMinor, NimPatch) >= (1, 6, 0):
    s.delete(idx..idx)
  else:
    s.delete(idx, idx)

#--------------------------------------------------------------
# Component
#--------------------------------------------------------------

proc identDef(varname: NimNode, vartype: NimNode): NimNode =
  ## Return a property definition for an object.
  ## 
  ## type
  ##   Foo = object
  ##     varname*: vartype <-- this is the AST being returned
  return nnkIdentDefs.newTree(
    nnkPostfix.newTree(
      ident("*"),
      varname,
    ),
    vartype,
    newEmptyNode()
  )

proc propDefinitions(c: Component): seq[NimNode] =
  ## Return the type of this component as will be put in the
  ## parser return type object definition
  ## 
  ## type
  ##   Foo = object
  ##     name*: string <-- this is the AST being returned
  let varname = ident(c.varname.safeIdentStr)
  case c.kind
  of ArgFlag:
    if c.flagMultiple:
      result.add identDef(varname, ident("int"))
    else:
      result.add identDef(varname, ident("bool"))
  of ArgOption:
    if c.optMultiple:
      result.add identDef(varname, parseExpr("seq[string]"))
    else:
      result.add identDef(varname, ident("string"))
      result.add identDef(
        ident(safeIdentStr(c.varname & "_opt")),
        nnkBracketExpr.newTree(
          ident("Option"),
          ident("string")
        )
      )
  of ArgArgument:
    if c.nargs != 1:
      result.add identDef(varname, parseExpr("seq[string]"))
    else:
      result.add identDef(varname, ident("string"))

#--------------------------------------------------------------
# Builder
#--------------------------------------------------------------

proc newBuilder*(name = ""): Builder =
  new(result)
  result.name = name
  result.symbol = genSym(nskLet, if name == "": "Argparse" else: name.safeIdentStr).toStrLit.strVal
  result.children = newSeq[Builder]()
  result.runProcBodies = newSeq[NimNode]()
  result.components.add Component(
    kind: ArgFlag,
    varname: "argparse_help",
    shortCircuit: true,
    flagShort: "-h",
    flagLong: "--help",
  )

proc `$`*(b: Builder): string = $(b[])

proc optsIdent(b: Builder): NimNode =
  ## Name of the option type for this Builder
  # let name = if b.name == "": "Argparse" else: b.name
  ident("Opts" & b.symbol)

proc parserIdent(b: Builder): NimNode =
  ## Name of the parser type for this Builder
  # let name = if b.name == "": "Argparse" else: b.name
  ident("Parser" & b.symbol)

proc optsTypeDef*(b: Builder): NimNode =
  ## Generate the type definition for the return value of parsing:
  var properties = nnkRecList.newTree()
  for component in b.components:
    if component.kind == ArgFlag:
      if component.shortCircuit:
        # don't add shortcircuits to the option type
        continue
    properties.add(component.propDefinitions())
  if b.parent.isSome:
    properties.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(
        ident("*"),
        ident("parentOpts")
      ),
      nnkRefTy.newTree(
        b.parent.get().optsIdent,
      ),
      newEmptyNode()
    )
  
  if b.children.len > 0:
    # .argparse_command
    properties.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(
        ident("*"),
        ident("argparse_command"),
      ),
      ident("string"),
      newEmptyNode(),
    )

  # subcommand opts
  for child in b.children:
    let childOptsIdent = child.optsIdent()
    properties.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(
        ident("*"),
        ident("argparse_" & child.name.toVarname() & "_opts")
      ),
      nnkBracketExpr.newTree(
        ident("Option"),
        nnkRefTy.newTree(childOptsIdent)
      ),
      newEmptyNode()
    )

  # type MyOpts = object
  result = nnkTypeDef.newTree(
    b.optsIdent(),
    newEmptyNode(),
    nnkObjectTy.newTree(
      newEmptyNode(),
      newEmptyNode(),
      properties,
    )
  )

proc parserTypeDef*(b: Builder): NimNode =
  ## Generate the type definition for the Parser object:
  ## 
  ## type
  ##   MyParser = object
  result = nnkTypeDef.newTree(
    b.parserIdent(),
    newEmptyNode(),
    nnkObjectTy.newTree(
      newEmptyNode(),
      newEmptyNode(),
      newEmptyNode(),
    )
  )

proc raiseShortCircuit*(flagname: string, help: string) {.inline.} =
  var e: ref ShortCircuit
  new(e)
  e.flag = flagname
  e.msg = "ShortCircuit on " & flagname
  e.help = help
  raise e

proc parseProcDef*(b: Builder): NimNode =
  ## Generate the parse proc for this Builder
  ## 
  ## proc parse(p: MyParser, args: seq[string]): MyOpts =
  result = newStmtList()
  
  let parserIdent = b.parserIdent()
  let optsIdent = b.optsIdent()
  
  # flag/opt/arg handlers
  var flagCase = newCaseStatement(parseExpr("token"))
  var optCase = newCaseStatement(parseExpr("key"))
  var requiredOptionGuard = newStmtList()
  var setDefaults = newStmtList()
  var filler = newArgFiller()
  for component in b.components:
    case component.kind
    of ArgFlag:
      var matches: seq[string]
      if component.flagShort != "":
        matches.add(component.flagShort)  # of "-h":
      if component.flagLong != "":
        matches.add(component.flagLong)   # of "--help":
      var body = newStmtList()
      if component.shortCircuit:
        let varname = newStrLitNode(component.varname)
        body.add quote do:
          raiseShortCircuit(`varname`, parser.help)
      else:
        if component.flagMultiple:
          let varname = ident(component.varname)
          body.add quote do:
            opts.`varname`.inc()
            state.consume(ArgFlag)
            continue
        else:
          let varname = ident(component.varname)
          body.add quote do:
            opts.`varname` = true
            state.consume(ArgFlag)
            continue
      if not body.isNil:
        flagCase.add(matches, body)
    of ArgOption:
      let varname = ident(component.varname)
      let varname_opt = ident(component.varname & "_opt")
      if component.env != "":
        # Set default from environment variable
        let dft = newStrLitNode(component.optDefault.get(""))
        let env = newStrLitNode(component.env)
        setDefaults.add quote do:
          opts.`varname` = getEnv(`env`, `dft`)
        if component.optDefault.isSome:
          setDefaults.add quote do:
            opts.`varname_opt` = some(getEnv(`env`, `dft`))
      elif component.optDefault.isSome:
        # Set default
        let dft = component.optDefault.get()
        setDefaults.add quote do:
          opts.`varname` = `dft`
          opts.`varname_opt` = some(`dft`)
      var matches: seq[string]
      var optCombo: string
      if component.optShort != "":
        matches.add(component.optShort)   # of "-h"
        optCombo.add component.optShort
      if component.optLong != "":
        matches.add(component.optLong)    # of "--help"
        if optCombo != "":
          optCombo.add ","
        optCombo.add(component.optLong)
      let optComboNode = newStrLitNode(optCombo)

      # Make sure it has a value
      let valueGuard = quote do:
        if state.value.isNone:
          raise UsageError.newException("Missing value for " & `optComboNode`)

      # Make sure it in the set of expected choices
      var choiceGuard = parseExpr("discard \"no choice guard\"")
      if component.optChoices.len > 0:
        let choices = component.optChoices
        choiceGuard = quote do:
          if state.value.get() notin `choices`:
            raise UsageError.newException("Invalid value for " & `optComboNode` & ": " & state.value.get() & " (valid choices: " & $`choices` & ")")
      
      # Make sure required options have been provided
      if component.optRequired:
        let envStr = newStrLitNode(component.env)
        requiredOptionGuard.add quote do:
          if `optComboNode` notin switches_seen and (`envStr` == "" or getEnv(`envStr`) == ""):
            raise UsageError.newException("Option " & `optComboNode` & " is required and was not provided")

      # Make sure it hasn't been provided twice
      var duplicateGuard: NimNode
      var body: NimNode
      if component.optMultiple:
        # -o apple -o banana
        duplicateGuard = parseExpr("discard \"no duplicate guard\"")
        body = quote do:
          opts.`varname`.add(state.value.get())
          state.consume(ArgOption)
          continue
      else:
        # -o single
        duplicateGuard = quote do:
          if `optComboNode` in switches_seen:
            raise UsageError.newException("Option " & `optComboNode` & " supplied multiple times")
          switches_seen.add(`optComboNode`)
        body = quote do:
          opts.`varname` = state.value.get()
          opts.`varname_opt` = some(opts.`varname`)
          state.consume(ArgOption)
          continue
      if not body.isNil:
        optCase.add(matches, newStmtList(
          valueGuard,
          choiceGuard,
          duplicateGuard,
          body,
        ))
    of ArgArgument:
      # Process positional arguments
      if component.nargs == -1:
        filler.wildcard(component.varname)
      elif component.nargs == 1:
        let varname = ident(component.varname)
        if component.env != "":
          filler.optional(component.varname)
          let envStr = newStrLitNode(component.env)
          let dftStr = newStrLitNode(component.argDefault.get(""))
          setDefaults.add replaceNodes(quote do:
            opts.`varname` = getEnv(`envStr`, `dftStr`)
          )
        elif component.argDefault.isSome:
          filler.optional(component.varname)
          let dftStr = newStrLitNode(component.argDefault.get())
          setDefaults.add replaceNodes(quote do:
            opts.`varname` = `dftStr`
          )
        else:
          filler.required(component.varname, 1)
      elif component.nargs > 1:
        filler.required(component.varname, component.nargs)
  
  # args proc
  let minArgs = newIntLitNode(filler.minArgs)
  var argcase = newCaseStatement(parseExpr("state.extra.len"))
  if filler.minArgs > 0:
    for nargs in 0..<filler.minArgs:
      let missing = newStrLitNode(filler.missing(nargs).join(", "))
      argcase.add(nargs, replaceNodes(quote do:
        raise UsageError.newException("Missing argument(s): " & `missing`)
      ))
  let upperBreakpoint = filler.upperBreakpoint
  for nargs in filler.minArgs..upperBreakpoint:
    let channels = filler.channels(nargs)
    var s = newStmtList()
    for ch in filler.channels(nargs):
      let varname = ident(ch.dest)
      case ch.kind
      of Wildcard:
        let argsAfterWildcard = newIntLitNode(filler.numArgsAfterWildcard)
        s.add replaceNodes(quote do:
          for i in 0..<(state.extra.len - `argsAfterWildcard`):
            opts.`varname`.add state.extra.popleft()
        )
      else:
        for i in 0..<ch.idx.len:
          s.add replaceNodes(quote do:
            opts.`varname`.setOrAdd state.extra.popleft()
          )
    if nargs == upperBreakpoint:
      argcase.addElse(s)
    else:
      argcase.add(nargs, s)

  # commands
  var commandCase = newCaseStatement(parseExpr("token"))
  for child in b.children:
    if filler.hasVariableArgs:
      raise ValueError.newException("Mixing optional args with commands is not supported")
    let childParserIdent = child.parserIdent()
    let childOptsIdent = child.optsIdent()
    let childNameStr = child.name.newStrLitNode()
    let subopts_prop_name = ident("argparse_" & child.name.toVarname & "_opts")
    commandCase.add(child.name, replaceNodes(quote do:
      ## Call the subcommand's parser
      takeArgsFromExtra(opts, state)
      argsTaken = true
      opts.argparse_command = `childNameStr`
      state.consume(ArgArgument)
      var subparser = `childParserIdent`()
      var subOpts: ref `childOptsIdent`
      new(subOpts)
      subOpts.parentOpts = opts
      opts.`subopts_prop_name` = some(subOpts)
      subparser.parse(subOpts, state, runblocks = runblocks, quitOnHelp = quitOnHelp, output = output)
      continue
    ))
  
  var addRunProcs = newStmtList()
  var runProcs = newStmtList()
  for p in b.runProcBodies:
    addRunProcs.add(quote do:
      state.runProcs.add(proc() =
        `p`
      ))
  if b.parent.isNone:
    runProcs.add(quote do:
      if runblocks:
        for p in state.runProcs:
          p()
    )

  proc mkCase(c: ref UnfinishedCase): NimNode =
    if c.isValid and not c.hasElse:
      c.addElse(parseExpr("discard"))
    result = replaceNodes(c.finalize())
    if result.isNil:
      result = parseExpr("discard")

  var flagCase_node = mkCase(flagCase)
  var optCase_node = mkCase(optCase)
  var argCase_node = mkCase(argCase)
  var commandCase_node = mkCase(commandCase)

  var parseProc = quote do:
    proc parse(parser: `parserIdent`, opts: ref `optsIdent`, state: ref ParseState, runblocks = false, quitOnHelp = true, output:Stream = ARGPARSE_STDOUT) {.used.} =
      try:
        var switches_seen {.used.} : seq[string]
        proc takeArgsFromExtra(opts: ref `optsIdent`, state: ref ParseState) =
          `requiredOptionGuard`
          `argCase_node`
        # Set defaults
        `setDefaults`
        `addRunProcs`
        var argCount {.used.} = 0
        var argsTaken = false
        var doneProcessingFlags = false
        while not state.done:
          # handle no-argument flags and commands
          let token {.used.} = state.token.get()
          if not doneProcessingFlags:
            `flagCase_node`
            # handle argument-taking flags
            let key {.used.} = state.key.get()
            `optCase_node`
          if state.extra.len >= `minArgs`:
            `commandCase_node`
          if token == "--":
            doneProcessingFlags = true
            state.consume(ArgArgument)
            continue
          state.skip()
        if not argsTaken:
          takeArgsFromExtra(opts, state)
        if state.extra.len > 0:
          # There are extra args.
          raise UsageError.newException("Unknown argument(s): " & state.extra.join(", "))
        `runProcs`
      except ShortCircuit as e:
        if e.flag == "argparse_help" and runblocks:
          output.write(parser.help())
          if quitOnHelp:
            quit(1)
        else:
          raise e

  result.add(replaceNodes(parseProc))

  # Convenience parse/run procs
  result.add replaceNodes(quote do:
    proc parse(parser: `parserIdent`, args: seq[string], quitOnHelp = true): ref `optsIdent` {.used.} =
      ## Parse arguments using the `parserIdent` parser
      var state = newParseState(args)
      var opts: ref `optsIdent`
      new(opts)
      parser.parse(opts, state, quitOnHelp = quitOnHelp)
      result = opts
  )
  # proc parse() with no args
  result.add replaceNodes(quote do:
    proc parse(parser: `parserIdent`, quitOnHelp = true): ref `optsIdent` {.used.} =
      ## Parse command line params
      when declared(commandLineParams):
        parser.parse(toSeq(commandLineParams()), quitOnHelp = quitOnHelp)
      else:
        var params: seq[string]
        for i in 0..paramCount():
          params.add(paramStr(i))
        parser.parse(params, quitOnHelp = quitOnHelp)
  )
  result.add replaceNodes(quote do:
    proc run(parser: `parserIdent`, args: seq[string], quitOnHelp = true, output:Stream = ARGPARSE_STDOUT) {.used.} =
      ## Run the matching run-blocks of the parser
      var state = newParseState(args)
      var opts: ref `optsIdent`
      new(opts)
      parser.parse(opts, state, runblocks = true, quitOnHelp = quitOnHelp, output = output)
  )
  # proc run() with no args
  result.add replaceNodes(quote do:
    proc run(parser: `parserIdent`) {.used.} =
      ## Run the matching run-blocks of the parser
      when declared(commandLineParams):
        parser.run(toSeq(commandLineParams()))
      else:
        var params: seq[string]
        for i in 0..paramCount():
          params.add(paramStr(i))
        parser.run(params)
  )

  # Shorter named convenience procs
  if b.children.len > 0:
    # .argparse_command -> .command shortcut
    result.add replaceNodes(quote do:
      proc command(opts: ref `optsIdent`): string {.used, inline.} =
        opts.argparse_command
    )

  # .argparse_NAME_opts -> .NAME shortcut
  for child in b.children:
    let name = ident(child.name)
    let fulloptname = ident("argparse_" & child.name.toVarname & "_opts")
    let retval = nnkBracketExpr.newTree(
      ident("Option"),
      nnkRefTy.newTree(child.optsIdent())
    )
    result.add replaceNodes(quote do:
      proc `name`(opts: ref `optsIdent`): `retval` {.used, inline.} =
        opts.`fulloptname`
    )

proc setOrAdd*(x: var string, val: string) =
  x = val

proc setOrAdd*(x: var seq[string], val: string) =
  x.add(val)

proc getHelpText*(b: Builder): string =
  ## Generate the static help text string
  if b.help != "":
    result.add(b.help)
    result.add("\L\L")

  # usage
  var usage_parts:seq[string]

  proc firstline(s:string):string =
    s.split("\L")[0]

  proc formatOption(flags:string, helptext:string, defaultval = none[string](), envvar:string = "", choices:seq[string] = @[], opt_width = 26, max_width = 100):string =
    result.add("  " & flags)
    var helptext = helptext
    if choices.len > 0:
      helptext.add(" Possible values: [" & choices.join(", ") & "]")
    if defaultval.isSome:
      helptext.add(&" (default: {defaultval.get()})")
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
  for comp in b.components:
    case comp.kind
    of ArgFlag:
      if not comp.hidden:
          var flag_parts: seq[string]
          if comp.flagShort != "":
            flag_parts.add(comp.flagShort)
          if comp.flagLong != "":
            flag_parts.add(comp.flagLong)
          opts.add(formatOption(flag_parts.join(", "), comp.help))
          opts.add("\L")
    of ArgOption:
      if not comp.hidden:
          var flag_parts: seq[string]
          if comp.optShort != "":
            flag_parts.add(comp.optShort)
          if comp.optLong != "":
            flag_parts.add(comp.optLong)
          var flags = flag_parts.join(", ") & "=" & comp.varname.toUpper()
          opts.add(formatOption(flags, comp.help, defaultval = comp.optDefault, envvar = comp.env, choices = comp.optChoices))
          opts.add("\L")
    of ArgArgument:
      var leftside:string
      if comp.nargs == 1:
        leftside = comp.varname
        if comp.argDefault.isSome:
          leftside = &"[{comp.varname}]"
      elif comp.nargs == -1:
        leftside = &"[{comp.varname} ...]"
      else:
        leftside = (&"{comp.varname} ").repeat(comp.nargs)
      usage_parts.add(leftside)
      args.add(formatOption(leftside, comp.help, defaultval = comp.argDefault, envvar = comp.env, opt_width=16))
      args.add("\L")
  
  var commands = newOrderedTable[string,string](2)

  if b.children.len > 0:
    usage_parts.add("COMMAND")
    for subbuilder in b.children:
      var leftside = subbuilder.name
      let group = subbuilder.groupName
      if not commands.hasKey(group):
        commands[group] = ""
      let indent = if group == "": "" else: "  "
      commands[group].add(indent & formatOption(leftside, subbuilder.help.firstline, opt_width=16))
      commands[group].add("\L")

  if usage_parts.len > 0 or opts != "":
    result.add("Usage:\L")
    result.add("  ")
    result.add(b.name & " ")
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

  result.stripLineEnd()

proc helpProcDef*(b: Builder): NimNode =
  ## Generate the help proc for the parser
  let helptext = b.getHelpText()
  let prog = newStrLitNode(b.name)
  let parserIdent = b.parserIdent()
  result = newStmtList()
  result.add replaceNodes(quote do:
    proc help(parser: `parserIdent`): string {.used.} =
      ## Get the help string for this parser
      var prog = `prog`
      if prog == "":
        prog = getAppFilename().extractFilename()
      result.add `helptext`.replace("{prog}", prog)
  )

type
  GenResponse* = tuple
    types: NimNode
    procs: NimNode
    instance: NimNode

proc addParser*(name: string, group: string, content: proc()): Builder =
  ## Add a parser (whether main parser or subcommand) and return the Builder
  ## Call ``generateDefs`` to get the type and proc definitions.
  builderStack.add newBuilder(name)
  content()
  var builder = builderStack.pop()
  builder.groupName = group
  if builder.help == "" and builderStack.len == 0:
    builder.help = "{prog}"

  if builderStack.len > 0:
    # subcommand
    builderStack[^1].children.add(builder)
    builder.parent = some(builderStack[^1])
  
  return builder

proc add_runProc*(body: NimNode) {.compileTime.} =
  ## Add a run block proc to the current parser
  builderStack[^1].runProcBodies.add(replaceNodes(body))

proc add_command*(name: string, group: string, content: proc()) {.compileTime.} =
  ## Add a subcommand to a parser
  discard addParser(name, group, content)

proc allChildren*(builder: Builder): seq[Builder] =
  ## Return all the descendents of this builder
  for child in builder.children:
    result.add child
    result.add child.allChildren()

proc generateDefs*(builder: Builder): NimNode =
  ## Generate the AST definitions for the current builder
  result = newStmtList()
  var typeSection = nnkTypeSection.newTree()
  var procsSection = newStmtList()
  
  # children first to avoid forward declarations
  for child in builder.allChildren().reversed:
    typeSection.add child.optsTypeDef()
    typeSection.add child.parserTypeDef()
    procsSection.add child.helpProcDef()
    procsSection.add child.parseProcDef()

  #   MyOpts = object
  typeSection.add builder.optsTypeDef()
  #   MyParser = object
  typeSection.add builder.parserTypeDef()

  # proc help(p: MyParser, ...)
  # proc parse(p: MyParser, ...)
  # proc run(p: MyParser, ...)
  procsSection.add builder.helpProcDef()
  procsSection.add builder.parseProcDef()

  # let parser = MyParser()
  # parser
  let parserIdent = builder.parserIdent()
  let instantiationSection = quote do:
    var parser = `parserIdent`()
    parser
  
  result.add(typeSection)
  result.add(procsSection)
  result.add(instantiationSection)

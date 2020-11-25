import algorithm; export algorithm
import macros
import options; export options
import sequtils
import streams
import strformat
import strutils
import tables

import ./macrohelp

type
  UsageError* = object of ValueError
  ShortCircuit* = object of CatchableError

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
    components*: seq[Component]
    help*: string
    groupName*: string
    children*: seq[Builder]
    parent*: Option[Builder]
  
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

var ARGPARSE_STDOUT* = newFileStream(stdout)
var builderStack* {.compileTime.} = newSeq[Builder]()

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
  else:
    let token = state.tokens[state.cursor]
    state.token = some(token)
    if token.startsWith("-") and '=' in token:
      let parts = token.split("=", 1)
      state.key = some(parts[0])
      state.value = some(parts[1])
    else:
      state.key = some(token)
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
    state.advance(2)
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
  s.delete(0, 0)

proc popright*[T](s: var seq[T], n = 0): T =
  ## Pop the nth item from the end of a seq
  let idx = s.len - n - 1
  result = s[idx]
  s.delete(idx, idx)

#--------------------------------------------------------------
# Component
#--------------------------------------------------------------

proc propDefinition(c: Component): NimNode =
  ## Return the type of this component as will be put in the
  ## parser return type object definition
  ## 
  ## type
  ##   Foo = object
  ##     name*: string <-- this is the AST being returned
  var val: NimNode
  case c.kind
  of ArgFlag:
    if c.flagMultiple:
      val = ident("int")
    else:
      val = ident("bool")
  of ArgOption:
    if c.optMultiple:
      val = parseExpr("seq[string]")
    else:
      val = ident("string")
  of ArgArgument:
    if c.nargs != 1:
      val = parseExpr("seq[string]")
    else:
      val = ident("string")
  # name*: type
  return nnkIdentDefs.newTree(
    nnkPostfix.newTree(
      ident("*"),
      ident(c.varname.safeIdentStr)
    ),
    val,
    newEmptyNode()
  )

#--------------------------------------------------------------
# Builder
#--------------------------------------------------------------

proc newBuilder*(name = ""): Builder =
  new(result)
  result.name = name
  result.children = newSeq[Builder]()
  result.components.add Component(
    kind: ArgFlag,
    varname: "help",
    shortCircuit: true,
    flagShort: "-h",
    flagLong: "--help",
  )

proc `$`*(b: Builder): string = $(b[])

proc optsIdent(b: Builder): NimNode =
  ## Name of the option type for this Builder
  let name = if b.name == "": "Argparse" else: b.name
  ident(name.safeIdentStr & "Opts")

proc parserIdent(b: Builder): NimNode =
  ## Name of the parser type for this Builder
  let name = if b.name == "": "Argparse" else: b.name
  ident(name.safeIdentStr & "Parser")

proc optsTypeDef*(b: Builder): NimNode =
  ## Generate the type definition for the return value of parsing:
  ## 
  ## type
  ##   MyParserOpts = object
  ##     flag1*: bool
  ##     arg1*: string
  var properties = nnkRecList.newTree()
  for component in b.components:
    properties.add(component.propDefinition())
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
  var setDefaults = newStmtList()
  var argsFromBeginning = true
  var argStatements = newStmtList()
  var revArgStatements: seq[NimNode] # statements that will be run backward
  var greedyArgStatement = newStmtList() # final arg statement that will eat the rest of the args
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
          if runblocks:
            raise ShortCircuit.newException(`varname`)
      if component.flagMultiple:
        let varname = ident(component.varname)
        body.add quote do:
          result.`varname`.inc()
          state.consume(ArgFlag)
          continue
      else:
        let varname = ident(component.varname)
        body.add quote do:
          result.`varname` = true
          state.consume(ArgFlag)
          continue
      if not body.isNil:
        flagCase.add(matches, body)
    of ArgOption:
      let varname = ident(component.varname)
      if component.env != "":
        # Set default from environment variable
        let dft = newStrLitNode(component.optDefault.get(""))
        let env = newStrLitNode(component.env)
        setDefaults.add quote do:
          result.`varname` = getEnv(`env`, `dft`)
      elif component.optDefault.isSome:
        # Set default
        let dft = component.optDefault.get()
        setDefaults.add quote do:
          result.`varname` = `dft`
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
      var choiceGuard = parseExpr("discard")
      if component.optChoices.len > 0:
        let choices = component.optChoices
        choiceGuard = quote do:
          if state.value.get() notin `choices`:
            raise UsageError.newException("Invalid value for " & `optComboNode` & ": " & state.value.get() & " (valid choices: " & $`choices` & ")")

      # Make sure it hasn't been provided twice
      var duplicateGuard: NimNode
      var body: NimNode
      if component.optMultiple:
        # -o apple -o banana
        duplicateGuard = parseExpr("discard")
        body = quote do:
          result.`varname`.add(state.value.get())
          state.consume(ArgOption)
          continue
      else:
        # -o single
        duplicateGuard = quote do:
          if `optComboNode` in switches_seen:
            raise UsageError.newException("Option " & `optComboNode` & " supplied multiple times")
          switches_seen.add(`optComboNode`)
        body = quote do:
          result.`varname` = state.value.get()
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
      # Process arguments
      let varname = ident(component.varname)
      var varnameStr = newStrLitNode(component.varname)
      var defaultOrFail = parseExpr("discard")
      if component.env != "":
        let dft = newStrLitNode(component.argDefault.get(""))
        let envvar = newStrLitNode(component.env)
        defaultOrFail = quote do:
          result.`varname` = getEnv(`envvar`, `dft`)
      elif component.argDefault.isSome:
        let dft = newStrLitNode(component.argDefault.get())
        defaultOrFail = quote do:
          result.`varname` = `dft`
      else:
        defaultOrFail = quote do:
          raise UsageError.newException("Missing value for arg: " & `varnameStr`)
      if component.nargs == 1:
        if argsFromBeginning:
          argStatements.add quote do:
            try:
              result.`varname` = extra.popleft()
            except:
              `defaultOrFail`
        else:
          revArgStatements.add quote do:
            try:
              result.`varname` = extra.pop()
            except:
              `defaultOrFail`
      elif component.nargs >= 1:
        if argsFromBeginning:
          for i in 0..<component.nargs:
            argStatements.add quote do:
              try:
                result.`varname`.add extra.popleft()
              except:
                `defaultOrFail`
        else:
          var stmts = newStmtList()
          for i in 0..<component.nargs:
            stmts.add quote do:
              try:
                result.`varname`.add extra.pop()
              except:
                `defaultOrFail`
          stmts.add quote do:
            result.`varname`.reverse()
          revArgStatements.add stmts
      elif component.nargs == -1:
        if argsFromBeginning:
          argsFromBeginning = false # start to take args from the end
          greedyArgStatement = quote do:
            while extra.len > 0:
              result.`varname`.add extra.popleft()
        else:
          raise ValueError.newException("Only one nargs=-1 arg is allowed. Second one is: " & component.varname)
    else:
      discard
  
  revArgStatements.reverse()
  var revArgStatementsNode = newStmtList(revArgStatements)

  if flagCase.isValid:
    flagCase.addElse(parseExpr("discard"))
  var flagCase_node = replaceNodes(flagCase.finalize())
  if flagCase_node.isNil:
    flagCase_node = parseExpr("discard")
  
  if optCase.isValid:
    optCase.addElse(parseExpr("discard"))
  var optCase_node = replaceNodes(optCase.finalize())
  if optCase_node.isNil:
    optCase_node = parseExpr("discard")

  var parseProc = quote do:
    proc parse(parser: `parserIdent`, state: ref ParseState, runblocks = false, quitOnShortCircuit = true, output:Stream = ARGPARSE_STDOUT): `optsIdent` {.used.} =
      try:
        result = `optsIdent`()
        # Set defaults
        `setDefaults`
        var switches_seen {.used.} : seq[string]
        while not state.done:
          # handle no-argument flags
          let token {.used.} = state.token.get()
          `flagCase_node`
          # handle argument-taking flags
          let key {.used.} = state.key.get()
          `optCase_node`
          # TODO: handle args
          state.skip()
        var extra = state.extra
        # Take from the front of the args
        `argStatements`
        # Take from the back of the args
        `revArgStatementsNode`
        # Take the rest
        `greedyArgStatement`
        if extra.len > 0:
          # There are extra args.
          raise UsageError.newException("Unknown argument(s): " & $state.extra)
      except ShortCircuit:
        if getCurrentExceptionMsg() == "help":
          output.write(parser.help())
        if quitOnShortCircuit:
          quit(1)

  result.add(replaceNodes(parseProc))

  # Convenience procs
  result.add quote do:
    proc parse(parser: `parserIdent`, args: seq[string]): `optsIdent` {.used.} =
      ## Parse arguments using the `parserIdent` parser
      var state = newParseState(args)
      parser.parse(state)
  
  result.add quote do:
    proc run(parser: `parserIdent`, args: seq[string], quitOnShortCircuit = true, output:Stream = ARGPARSE_STDOUT) {.used.} =
      ## Run the matching run-blocks of the parser
      var state = newParseState(args)
      discard parser.parse(state, runblocks = true, quitOnShortCircuit = quitOnShortCircuit, output = output)

proc getHelpText*(b: Builder): string =
  ## Generate the static help text string
  result.add b.name # TODO: make this dynamically be $0 if desired
  result.add "\L\L"

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

  result.setLen(result.high) # equivalent to new Nim .stripLineEnd

proc helpProcDef*(b: Builder): NimNode =
  ## Generate the help proc for the parser
  let helptext = b.getHelpText()

  let parserIdent = b.parserIdent()
  result = newStmtList()
  result.add quote do:
    proc help(parser: `parserIdent`): string {.used.} =
      ## Get the help string for this parser
      `helptext`

type
  GenResponse* = tuple
    types: NimNode
    procs: NimNode
    instance: NimNode

proc mkParser*(name: string, group: string, content: proc(), instantiate = false): GenResponse =
  ## Generate the types and procs for this parser builder
  ## and all child parsers.
  
  builderStack.add newBuilder(name)
  content()
  var builder = builderStack.pop()
  builder.groupName = group
  
  # type
  var typeSection = nnkTypeSection.newTree()
  #   MyOpts = object
  #     ...
  typeSection.add builder.optsTypeDef()
  #   MyParser = object
  #     ...
  typeSection.add builder.parserTypeDef()
  
  # proc parse(p: MyParser, ...)
  # proc run(p: MyParser, ...)
  var procsSection = newStmtList()
  
  procsSection.add builder.helpProcDef()
  procsSection.add builder.parseProcDef()

  # let parser = MyParser()
  var instantiationSection = parseExpr("discard")
  if instantiate:
    let parserIdent = builder.parserIdent()
    instantiationSection = quote do:
      var parser = `parserIdent`()
      parser

  result = (typeSection, procsSection, instantiationSection)

  if builderStack.len > 0:
    # subcommand
    builderStack[^1].children.add(builder)
    builder.parent = some(builderStack[^1])

proc add_command*(name: string, group: string, content: proc()) {.compileTime.} =
  discard mkParser(name, group, content)

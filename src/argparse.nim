## argparse is an explicit, strongly-typed command line argument parser.
##
## Use ``newParser`` to create a parser.  Within the body
## of the parser use the following procs/templates (read the individual
## documentation below for more details):
##
## ===================  ===================================================
## Proc                 Description
## ===================  ===================================================
## ``flag(...)``        boolean flag (e.g. ``--dryrun``)
## ``option(...)``      option with argument (e.g. ``--output foo``)
## ``arg(...)``         positional argument (e.g. ``file1 file2``)
## ``help(...)``        add a help string to the parser or subcommand
## ``command "NAME":``  add a sub command
## ``run:``             code to run when the parser is used in run mode
## ``nohelpflag()``     disable the automatic ``-h/--help`` flag
## ===================  ===================================================
## 
## The following special variables are available within ``run`` blocks:
##
## - ``opts`` - contains your user-defined options. Same thing as returned from ``parse(...)`` scoped to the subcommand.
## - ``opts.parentOpts`` - a reference to parent options (i.e. from a subcommand)
## - ``opts.argparse_command`` - a string holding the chosen command
## - ``opts.command`` - same as above (if there is no flag/option/arg named ``"command"``)
## - ``opts.argparse_NAMEOFCOMMAND_opts`` - an ``Option[...]`` that will hold the options for the command named ``NAMEOFCOMMAND``
## - ``opts.NAMEOFCOMMAND`` - Same as above, but a shorter version (if there's no name conflict with other flags/options/args)
##
## If ``Parser.parse()`` and ``Parser.run()`` are called without arguments, they use the arguments from the command line.
## 
## By default (unless ``nohelpflag`` is present) calling ``parse()`` with a help
## flag (``-h`` / ``--help``) will raise a ``ShortCircuit`` error.  The error's ``flag``
## field will contain the name of the flag that triggered the short circuit.
## For help-related short circuits, the error's ``help`` field will contain the help text
## of the given subcommand.
## 
runnableExamples:
  var res:string
  var p = newParser:
    help("A demonstration of this library in a program named {prog}")
    flag("-n", "--dryrun")
    option("--name", default=some("bob"), help = "Name to use")
    command("ls"):
      run:
        res = "did ls " & opts.parentOpts.name
    command("run"):
      option("-c", "--command")
      run:
        let name = opts.parentOpts.name
        if opts.parentOpts.dryrun:
          res = "would have run: " & opts.command & " " & name
        else:
          res = "ran " & opts.command & " " & name
  try:
    p.run(@["-n", "run", "--command", "something"])
  except UsageError:
    stderr.writeLine getCurrentExceptionMsg()
    quit(1)
  assert res == "would have run: something bob"

runnableExamples:
  var p = newParser:
    help("A description of this program, named {prog}")
    flag("-n", "--dryrun")
    option("-o", "--output", help="Write output to this file", default=some("somewhere.txt"))
    option("-k", "--kind", choices = @["fruit", "vegetable"])
    arg("input")
  
  try:
    let opts = p.parse(@["-n", "--output", "another.txt", "cranberry"])
    assert opts.dryrun == true
    assert opts.output == "another.txt"
    assert opts.input == "cranberry"
  except ShortCircuit as err:
    if err.flag == "argparse_help":
      echo err.help
      quit(1)
  except UsageError:
    stderr.writeLine getCurrentExceptionMsg()
    quit(1)

runnableExamples:
  var p = newParser:
    command "go":
      flag("-a")
    command "leave":
      flag("-b")
  
  let opts = p.parse(@["go", "-a"])
  assert opts.command == "go"
  assert opts.go.isSome
  assert opts.go.get.a == true
  assert opts.leave.isNone

import std/macros
import strutils
import argparse/backend; export backend
import argparse/macrohelp; export macrohelp

proc longAndShort(name1: string, name2: string): tuple[long: string, short: string] =
  ## Given two strings, return the longer and shorter of the two with
  ## shortname possibly being empty.
  var
    longname: string
    shortname: string
  if name2 == "":
    longname = name1
  else:
    if name1.len > name2.len:
      longname = name1
      shortname = name2
    else:
      longname = name2
      shortname = name1
  return (longname, shortname)

template newParser*(name: string, body: untyped): untyped =
  ## Create a new parser with a static program name.
  ##
  runnableExamples:
    var p = newParser("my parser"):
      help("'{prog}' == 'my parser'")
      flag("-a")
    assert p.parse(@["-a"]).a == true

  macro domkParser() : untyped {.gensym.} =
    let builder = addParser(name, "", proc() = body)
    builder.generateDefs()
  domkParser()

template newParser*(body: untyped): untyped =
  ## Create a new command-line parser named the same as the current executable.
  ##
  runnableExamples:
    var p = newParser:
      flag("-a")
    assert p.parse(@["-a"]).a == true

  macro domkParser(): untyped =
    let builder = addParser("", "", proc() = body)
    builder.generateDefs()
  domkParser()

proc flag*(name1: string, name2 = "", multiple = false, help = "", hidden = false, shortcircuit = false) {.compileTime.} =
  ## Add a boolean flag to the argument parser.  The boolean
  ## will be available on the parsed options object as the
  ## longest named flag.
  ##
  ## If ``multiple`` is true then the flag can be specified multiple
  ## times and the datatype will be an int.
  ##
  ## If ``hidden`` is true then the flag usage is not shown in the help.
  ## 
  ## If ``shortcircuit`` is true, then when the flag is encountered during
  ## processing, the parser will immediately raise a ``ShortCircuit`` error
  ## with the ``flag`` attribute set to this flag's name.  This is how the
  ## default help flag is implemented.
  ##
  ## ``help`` is additional help text for this flag.
  runnableExamples:
    var p = newParser("Some Thing"):
      flag("--show-name", help="Show the name")
      flag("-a", help="Some flag named a")
      flag("-n", "--dryrun", help="Don't actually run")
    
    let opts = p.parse(@["--show-name", "-n"])
    assert opts.show_name == true
    assert opts.a == false
    assert opts.dryrun == true

  let names = longAndShort(name1, name2)
  let varname = names.long.toVarname()
  builderStack[^1].components.add Component(
    kind: ArgFlag,
    help: help,
    varname: varname,
    flagShort: names.short,
    flagLong: names.long,
    flagMultiple: multiple,
    shortCircuit: shortcircuit,
    hidden: hidden,
  )

proc option*(name1: string, name2 = "", help = "", default = none[string](), env = "", multiple = false, choices: seq[string] = @[], required = false, hidden = false) {.compileTime.} =
  ## Add an option to the argument parser.  The longest
  ## named flag will be used as the name on the parsed
  ## result.
  ## 
  ## Additionally, an ``Option[string]`` named ``FLAGNAME_opt``
  ## will be available on the parse result.
  ##
  ## Set ``multiple`` to true to accept multiple options.
  ##
  ## Set ``default`` to the default string value.
  ## If the value can't be inferred at compile-time, insert it in the ``run``
  ## block while accesing the option with
  ## ``opts.FLAGNAME_opt.get(otherwise = RunTimeString)`` instead.
  ##
  ## Set ``env`` to an environment variable name to use as the default value
  ## 
  ## Set ``choices`` to restrict the possible choices.
  ## 
  ## Set ``required = true`` if this is a required option. Yes, calling
  ## it a "required option" is a paradox :)
  ##
  ## Set ``hidden`` to prevent the option usage listing in the help text.
  ##
  ## ``help`` is additional help text for this option.
  runnableExamples:
    var p = newParser:
      option("-a", "--apple", help="Name of apple")
    assert p.parse(@["-a", "5"]).apple == "5"
    assert p.parse(@[]).apple_opt.isNone
    assert p.parse(@["--apple", "6"]).apple_opt.get() == "6"

  let names = longAndShort(name1, name2)
  let varname = names.long.toVarname()
  builderStack[^1].components.add Component(
    kind: ArgOption,
    help: help,
    hidden: hidden,
    varname: varname,
    env: env,
    optShort: names.short,
    optLong: names.long,
    optMultiple: multiple,
    optDefault: default,
    optChoices: choices,
    optRequired: required,
  )

proc arg*(varname: string, default = none[string](), env = "", help = "", nargs = 1) {.compileTime.} =
  ## Add an argument to the argument parser.
  ##
  ## Set ``default`` to the default ``Option[string]`` value.  This is only
  ## allowed for ``nargs = 1``.
  ##
  ## Set ``env`` to an environment variable name to use as the default value. This is only allowed for ``nargs = 1``.
  ## 
  ## The value ``nargs`` has the following meanings:
  ## 
  ## - ``nargs = 1`` : A single argument. The value type will be ``string``
  ## - ``nargs = 2`` (or more) : Accept a specific number of arguments.  The value type will be ``seq[string]``
  ## - ``nargs = -1`` : Accept 0 or more arguments. Only one ``nargs = -1`` ``arg()`` is allowed per parser/command.
  ##
  ## ``help`` is additional help text for this argument.
  runnableExamples:
    var p = newParser:
      arg("name", help = "Name of apple")
      arg("twowords", nargs = 2)
      arg("more", nargs = -1)
    let res = p.parse(@["cameo", "hot", "dog", "things"])
    assert res.name == "cameo"
    assert res.twowords == @["hot", "dog"]
    assert res.more == @["things"]

  builderStack[^1].components.add Component(
    kind: ArgArgument,
    help: help,
    varname: varname.toVarname(),
    nargs: nargs,
    env: env,
    argDefault: default,
  )

proc help*(helptext: string) {.compileTime.} =
  ## Add help to a parser or subcommand.
  ## 
  ## You may use the special string ``{prog}`` within any help text, and it
  ## will be replaced by the program name.
  ##
  runnableExamples:
    var p = newParser:
      help("Some helpful description")
      command("dostuff"):
        help("More helpful information")
    echo p.help
  
  builderStack[^1].help &= helptext

proc nohelpflag*() {.compileTime.} =
  ## Disable the automatic ``-h``/``--help`` flag
  runnableExamples:
    var p = newParser:
      nohelpflag()

  builderStack[^1].components.del(0)

template run*(body: untyped): untyped =
  ## Add a run block to this command
  runnableExamples:
    var p = newParser:
      command("dostuff"):
        run:
          echo "Actually do stuff"

  add_runproc(replaceNodes(quote(body)))

template command*(name: string, group: string, content: untyped): untyped =
  ## Add a subcommand to this parser
  ## 
  ## ``group`` is a string used to group commands in help output
  runnableExamples:
    var p = newParser:
      command("dostuff", "groupA"): discard
      command("morestuff", "groupB"): discard
      command("morelikethefirst", "groupA"): discard
    echo p.help
  add_command(name, group) do ():
    content

template command*(name: string, content: untyped): untyped =
  ## Add a subcommand to this parser
  runnableExamples:
    var p = newParser:
      command("dostuff"):
        run:
          echo "Actually do stuff"
    p.run(@["dostuff"])
  command(name, "", content)


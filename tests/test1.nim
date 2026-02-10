import argparse
import macros
import os
import osproc
import sequtils
import streams
import strformat
import strutils
import unittest

import ./util

suite "flags":
  test "short flags":
    var p = newParser("some name"):
      flag("-a")
      flag("-b")
    
    check p.parse(shlex"-a").a == true
    check p.parse(shlex"-a").b == false
    check "some name" in p.help
    check "-a" in p.help
    check "-b" in p.help
  
  test "long flags":
    var p = newParser "some name":
      flag("--apple")
      flag("--banana")
    
    check p.parse(shlex"--apple").apple == true
    check p.parse(shlex"--apple").banana == false
    check p.parse(shlex"--banana").banana == true
    check "some name" in p.help
    check "--apple" in p.help
    check "--banana" in p.help
  
  test "short and long flags":
    var p = newParser "some name":
      flag("-a", "--apple")
      flag("--banana", "-b")
    
    check p.parse(shlex"--apple").apple == true
    check p.parse(shlex"--apple").banana == false
    check p.parse(shlex"-b").banana == true
    check "some name" in p.help
    check "--apple" in p.help
    check "-a" in p.help
    check "--banana" in p.help
    check "-b" in p.help
  
  test "multiple flags":
    var p = newParser:
      flag("-b", multiple=true)
    
    check p.parse(shlex("-b")).b == 1
    check p.parse(shlex("-b -b")).b == 2
    check p.parse(shlex("")).b == 0
  
  test "help text":
    var p = newParser:
      flag("-a", "--apple", help="Some apples")
      flag("--banana-split-and-ice-cream", help="More help")
      noCompletions()
      flag("-c", multiple=true)
    
    check "Some apples" in p.help
    check "More help" in p.help
  
  test "unknown flag":
    var p = newParser:
      flag("-a")
    expect UsageError:
      discard p.parse(shlex"-b")
  
  test "shortcircuit":
    var p = newParser:
      flag("-V", "--version", shortcircuit=true)
    
    try:
      p.run(shlex"--version")
      assert false, "Should not get here"
    except ShortCircuit as e:
      check e.flag == "version"

    try:
      discard p.parse(shlex"-V")
      assert false, "Should not get here"
    except ShortCircuit as e:
      check e.flag == "version"


suite "options":
  test "short options":
    var p = newParser:
      option("-a", help="Stuff")
    check p.parse(shlex"-a=5").a == "5"
    check p.parse(shlex"-a 5").a == "5"
    check p.parse(shlex"-a 5").a_opt.get() == "5"
    check p.parse(shlex"").a_opt.isNone

    check "Stuff" in p.help
  
  test "long options":
    var p = newParser:
      option("--apple")
    check p.parse(shlex"--apple=10").apple == "10"
    check p.parse(shlex"--apple 10").apple == "10"
    check p.parse(shlex"--apple 10").apple_opt.get() == "10"
    check p.parse(shlex"").apple_opt.isNone
  
  test "option default":
    var p = newParser:
      option("--category", default=some("pinball"))
    check p.parse(shlex"").category == "pinball"
    check p.parse(shlex"--category foo").category == "foo"
    check p.parse(shlex"").category_opt.get() == "pinball"
    check p.parse(shlex"--category foo").category_opt.get() == "foo"
  
  test "option default from env var":
    var p = newParser:
      option("--category", env="HELLO", default=some("who"))
    check "HELLO" in p.help
    check p.parse(shlex"").category == "who"
    check p.parse(shlex"").category_opt.get() == "who"
    withEnv("HELLO", "Adele"):
      check p.parse(shlex"").category == "Adele"
      check p.parse(shlex"").category_opt.get() == "Adele"
    check p.parse(shlex"--category hey").category == "hey"
    check p.parse(shlex"--category hey").category_opt.get() == "hey"
  
  test "unknown option":
    var p = newParser:
      option("-a")
    expect UsageError:
      discard p.parse(shlex"-b")
  
  test "multiple options on non-multi option":
    var p = newParser:
      option("-a")
      option("-b", default = some("something"))
    expect UsageError:
      discard p.parse(shlex"-a 10 -a 20")
    expect UsageError:
      discard p.parse(shlex"-b hey -b ho")
    check p.parse(shlex"-b foo").b == "foo"
  
  test "multiple options":
    var p = newParser:
      option("-a", multiple=true)
    check p.parse(shlex"-a 10 -a 20").a == @["10", "20"]
    check p.parse(shlex"").a == []
    check p.parse(shlex"-a 20").a == @["20"]
  
  test "choices":
    var p = newParser:
      option("-b", choices = @["first", "second", "third"])

    check p.parse(shlex"-b first").b == "first"
    expect UsageError:
      discard p.parse(shlex"-b unknown")
  
  test "choices multiple":
    var p = newParser:
      option("-b", multiple=true, choices = @["first", "second", "third"])

    check p.parse(shlex"-b first").b == @["first"]
    check p.parse(shlex"-b first -b second").b == @["first", "second"]

  test "option with - value argument":
    var p = newParser:
      option("-b")
    check p.parse(shlex"-b -").b == "-"
    check p.parse(shlex"-b -a").b == "-a"
  
  test "required options":
    var p = newParser:
      option("-b", "--bob", required = true)
    expect UsageError:
      discard p.parse(@[])
    check p.parse(shlex"-b foo").bob == "foo"
    check p.parse(shlex"-b foo").bob_opt.get() == "foo"
    check p.parse(@["-b", ""]).bob == ""
    check p.parse(@["-b", ""]).bob_opt.get() == ""
  
  test "required options still allow for --help":
    var p = newParser:
      help("Top level help")
      option("-b", required=true)
    expect ShortCircuit:
      discard p.parse(shlex"--help", quitOnHelp=false)
  
  test "required options provided by env":
    var p = newParser:
      option("-b", "--bob", env="BOB", required = true)
    withEnv("BOB", "something"):
      check p.parse(shlex"").bob == "something"
      check p.parse(shlex"--bob another").bob == "another"

suite "args":
  test "single, required arg":
    var p = newParser:
      arg("name")
    check p.parse(shlex"foo").name == "foo"
    check "name" in p.help
  
  test "args are required":
    var p = newParser:
      arg("name")
    expect UsageError:
      discard p.parse(shlex"")
  
  test "args with hyphens become underscores":
    var p = newParser:
      arg("some-arg")
    check p.parse(shlex"something").some_arg == "something"
  
  test "extra args is an error":
    var p = newParser:
      arg("only")
    expect UsageError:
      discard p.parse(shlex"one two")
  
  test "single arg with default":
    var p = newParser:
      arg("name", default=some("foo"))
    check p.parse(shlex"").name == "foo"
    check p.parse(shlex"something").name == "something"
  
  test "single arg with env default":
    var p = newParser:
      arg("name", env="SOMETHING", default=some("foo"))
    check "SOMETHING" in p.help
    check p.parse(shlex"").name == "foo"
    check p.parse(shlex"something").name == "something"
    withEnv("SOMETHING", "goober"):
      check p.parse(shlex"").name == "goober"
      check p.parse(shlex"something").name == "something"
  
  test "2 args":
    var p = newParser:
      arg("name")
      arg("age")
    check p.parse(shlex"foo bar").name == "foo"
    check p.parse(shlex"foo bar").age == "bar"
    check "name" in p.help
    check "age" in p.help
  
  test "arg help":
    var p = newParser:
      arg("name", help="Something")
    check "Something" in p.help
  
  test "optional required optional required optional wildcard":
    var p = newParser:
      arg("a", default=some("bob"))
      arg("b")
      arg("c", default=some("sam"))
      arg("d", nargs = 2)
      arg("e", default=some("al"))
      arg("w", nargs = -1)
    var r = p.parse(shlex"1 2 3")
    check r.a == "bob"
    check r.b == "1"
    check r.c == "sam"
    check r.d == @["2", "3"]
    check r.e == "al"
    check r.w.len == 0
    r = p.parse(shlex"1 2 3 4")
    check r.a == "1"
    check r.b == "2"
    check r.c == "sam"
    check r.d == @["3", "4"]
    check r.e == "al"
    check r.w.len == 0
    r = p.parse(shlex"1 2 3 4 5")
    check r.a == "1"
    check r.b == "2"
    check r.c == "3"
    check r.d == @["4", "5"]
    check r.e == "al"
    check r.w.len == 0
    r = p.parse(shlex"1 2 3 4 5 6")
    check r.a == "1"
    check r.b == "2"
    check r.c == "3"
    check r.d == @["4", "5"]
    check r.e == "6"
    check r.w.len == 0
    r = p.parse(shlex"1 2 3 4 5 6 7")
    check r.a == "1"
    check r.b == "2"
    check r.c == "3"
    check r.d == @["4", "5"]
    check r.e == "6"
    check r.w == @["7"]
    r = p.parse(shlex"1 2 3 4 5 6 7 8")
    check r.a == "1"
    check r.b == "2"
    check r.c == "3"
    check r.d == @["4", "5"]
    check r.e == "6"
    check r.w == @["7", "8"]

  test "r o w o r":
    var p = newParser:
      arg("a")
      arg("b", default = some("hey"))
      arg("c", nargs = -1)
      arg("d", default = some("sam"))
      arg("e", nargs = 2)
    var r = p.parse(shlex"1 2 3")
    check r.a == "1"
    check r.b == "hey"
    check r.c.len == 0
    check r.d == "sam"
    check r.e == @["2", "3"]
    r = p.parse(shlex"1 2 3 4")
    check r.a == "1"
    check r.b == "2"
    check r.c.len == 0
    check r.d == "sam"
    check r.e == @["3", "4"]
    r = p.parse(shlex"1 2 3 4 5")
    check r.a == "1"
    check r.b == "2"
    check r.c.len == 0
    check r.d == "3"
    check r.e == @["4", "5"]
    r = p.parse(shlex"1 2 3 4 5 6")
    check r.a == "1"
    check r.b == "2"
    check r.c == @["3"]
    check r.d == "4"
    check r.e == @["5", "6"]
    r = p.parse(shlex"1 2 3 4 5 6 7")
    check r.a == "1"
    check r.b == "2"
    check r.c == @["3", "4"]
    check r.d == "5"
    check r.e == @["6", "7"]

  test "nargs=2":
    var p = newParser:
      arg("name", nargs=2)
    check p.parse(shlex"a b").name == @["a", "b"]
  
  test "nargs=-1":
    var p = newParser:
      arg("thing", nargs = -1)
    check p.parse(shlex"").thing.len == 0
    check p.parse(shlex"a").thing == @["a"]
    check p.parse(shlex"a b c").thing == @["a", "b", "c"]

  test "nargs=-1 at the end":
    var p = newParser:
      arg("first")
      arg("thing", nargs = -1)
    check p.parse(shlex"first").thing.len == 0
    check p.parse(shlex"first a").thing == @["a"]
    check p.parse(shlex"first a b c").thing == @["a", "b", "c"]
  
  test "nargs=-1 in the middle":
    var p = newParser:
      arg("first")
      arg("thing", nargs = -1)
      arg("last")
    check p.parse(shlex"first last").thing.len == 0
    check p.parse(shlex"first a last").thing == @["a"]
    check p.parse(shlex"first a b c last").thing == @["a", "b", "c"]
  
  test "nargs=-1 at the beginning":
    var p = newParser:
      flag("-a")
      arg("thing", nargs = -1)
      arg("last", nargs = 2)
    check p.parse(shlex"last 2").thing.len == 0
    check p.parse(shlex"a last 2").thing == @["a"]
    check p.parse(shlex"a b c last 2").thing == @["a", "b", "c"]
    check p.parse(shlex"last 2").last == @["last", "2"]

  test "nargs=-1 nargs=2 nargs=2":
    var p = newParser:
      arg("first", nargs = -1)
      arg("middle", nargs = 2)
      arg("last", nargs = 2)
    check p.parse(shlex"a b c d").first.len == 0
    check p.parse(shlex"a b c d").middle == @["a", "b"]
    check p.parse(shlex"a b c d").last == @["c", "d"]
    check p.parse(shlex"a b c d e").first == @["a"]
    check p.parse(shlex"a b c d e").middle == @["b", "c"]
    check p.parse(shlex"a b c d e").last == @["d", "e"]
  
  test "nargs=-1 nargs=1 w/ default":
    var p = newParser:
      arg("first", nargs = -1)
      arg("last", default=some("hey"))
    check p.parse(shlex"").last == "hey"
    check p.parse(shlex"hoo").last == "hoo"
    check p.parse(shlex"a b goo").last == "goo"
  
  test "extra args":
    var p = newParser:
      arg("first")
      arg("extra", nargs = -1)
    let res = p.parse(shlex"a -b c -foo -d -e=goo app app")
    check res.first == "a"
    check res.extra == @["-b", "c", "-foo", "-d", "-e=goo", "app", "app"]
  
  test "-- extra args":
    var p = newParser:
      flag("-a", "--apple")
      option("-b", "--banana")
      arg("hi")
      arg("extra", nargs = -1)
    let res = p.parse(shlex("-a -b foo hi -- -a --apple -b --banana goofy glop"))
    check res.apple == true
    check res.banana == "foo"
    check res.hi == "hi"
    check res.extra == @["-a", "--apple", "-b", "--banana", "goofy", "glop"]

suite "autohelp":
  test "static prog name":
    var p = newParser("staticname"):
      help("{prog}")
    check "staticname" in p.help
  
  test "dynamic prog name":
    var p = newParser:
      help("{prog}")
    check getAppFilename().extractFilename() in p.help

  test "helpbydefault":
    var res:string
    var p = newParser:
      help("Top level help")
      flag("--foo")
      run:
        res.add("main ran")
      command("something"):
        help("sub help")
        flag("--bar")
        run:
          res.add("sub ran")
    
    var op = newStringStream("")
    echo "about to run p.run"
    p.run(shlex"-h", quitOnHelp = false, output = op)
    op.setPosition(0)
    var output = op.readAll()
    check "--foo" in output
    check "Top level help" in output
    check res == ""

    op = newStringStream("")
    p.run(shlex"something --help", quitOnHelp = false, output = op)
    op.setPosition(0)
    output = op.readAll()
    check "--bar" in output
    check "sub help" in output
    check res == ""
  
  test "nohelpflag":
    var res:string
    var p = newParser:
      nohelpflag()
      run:
        res.add("main ran")
      command("something"):
        nohelpflag()
        run:
          res.add("sub ran")
    
    expect UsageError:
      p.run(shlex"-h", quitOnHelp = false)
    
    expect UsageError:
      p.run(shlex"something --help", quitOnHelp = false)
  
  test "parse help":
    let
      p = newParser: discard
    expect ShortCircuit:
      try:
        discard p.parse(@["-h"])
      except ShortCircuit as e:
        check e.flag == "argparse_help"
        raise e
  
  test "subcommand help":
    var p = newParser:
      command "foo":
        help("foo sub help")
        flag("-a")
      command "bar":
        help("bar sub help")
        flag("-b")
    var found_help: string
    try:
      var opts = p.parse(@["foo", "--help"])
    except ShortCircuit as e:
      if e.flag == "argparse_help":
        found_help = e.help
    check "foo sub help" in found_help
    check "bar sub help" notin found_help

suite "commands":
  test "run":
    var res:string = "hello"

    var p = newParser:
      command "command1":
        help("Some help text")
        flag("-a")
        run:
          res = $opts.a

    p.run(shlex"command1 -a")
    check res == "true"
    p.run(shlex"command1")
    check res == "false"
  
  test "run only one":
    var res:string

    var p = newParser:
      command "command1":
        run:
          res.add("command1")
      run:
        if opts.argparse_command == "":
          res.add("root run")
    p.run(shlex"command1")
    check res == "command1"
    res.setLen(0)

    p.run(@[])
    check res == "root run"
  
  test "run order":
    var res:string
    var p = newParser:
      run: res.add("a")
      command "sub":
        run: res.add("b")
        command "sub2":
          run: res.add("c")
    p.run(shlex"sub sub2")
    check res == "abc"

  test "two commands":
    var res:string = ""

    var p = newParser:
      command "move":
        arg("howmuch")
        run:
          res = "moving " & opts.howmuch
      command "eat":
        arg("what")
        run:
          res = "you ate " & opts.what
    
    p.run(shlex"move 10")
    check res == "moving 10"
    p.run(shlex"eat apple")
    check res == "you ate apple"

  test "access parent":
    var res:string = ""
    var p = newParser:
      option("-a")
      command "sub":
        option("-a")
        run:
          res = &"{opts.parentOpts.a},{opts.a}" 
    p.run(shlex"-a parent sub -a child")
    check res == "parent,child"
  
  test "unknown command":
    var res:string = ""

    var p = newParser:
      command "sub":
        option("-a")
        run:
          res = "did run"
    expect UsageError:
      discard p.parse(shlex"madeupcommand")
    
    check res == ""
  
  test "command groups":
    var p = newParser:
      command("first", group = "groupA"):
        help "A first command"
        run: discard
      command("second", group = "groupB"):
        help "A second command"
        run: discard
      command("third", group="groupA"):
        help "A third command"
        run: discard
    
    check "groupA" in p.help
    check "groupB" in p.help
    echo p.help

  test "command group ordering":
    var p = newParser:
      command("a", group = "AA"): discard
      command("b", group = "BB"): discard
      command("c", group = "CC"): discard
      command("d", group = "DD"): discard
      command("e", group = "EE"): discard
      command("f", group = "FF"): discard
    let indexes = @["AA","BB","CC","DD","EE","FF"].mapIt(p.help.find(it))
    check indexes == indexes.sorted()

  test "sub sub sub":
    var res:string = ""
    var p = newParser:
      command("a"):
        command("b"):
          command("c"):
            run: res.add "hi from c"
    p.run(shlex"a b c")
    check res == "hi from c"

    res.setLen(0)
    p.run(shlex"a b")
    check res == ""
  
  test "arg and command":
    var res:string = ""
    var p = newParser:
      arg("something")
      command("a"):
        run:
          res.add opts.parentOpts.something
    p.run(shlex"hello a")
    check res == "hello"
    res.setLen(0)

    p.run(shlex"a a")
    check res == "a"
  
  test "blank default":
    var res: string
    var p = newParser:
      command "cat":
        arg("version", default = some(""))
        run:
          res.add(opts.version)
    p.run(shlex"cat")
    check res == ""
    p.run(shlex"cat foo")
    check res == "foo"

  test "same parser name":
    ## Parsers with the same name are allowed (and made unique)
    var p1 = newParser("jim"):
      flag("-a")
    var p2 = newParser("jim"):
      flag("-b")
    
    let r1 = p1.parse(shlex"-a")
    check r1.a == true
    let r2 = p2.parse(shlex"-b")
    check r2.b == true
  
  test "parse access to sub-opts":
    var p = newParser:
      command "foo":
        flag("-a")
      command "bar":
        flag("-b")
    let o1 = p.parse(shlex"foo -a")
    check o1.argparse_command == "foo" # conflict-unlikely version
    check o1.command == "foo" # shortcut version
    check o1.argparse_foo_opts.isSome # conflict-unlikely version
    check o1.foo.isSome # shortcut version
    check o1.foo.get.a == true
    
    check o1.argparse_bar_opts.isNone # conflict-unlikely version
    check o1.bar.isNone
  
  test "parse sub-opts name conflicts":
    var p = newParser:
      flag("--foo")
      arg("command") # why would you do this? :)
      command "foo":
        flag("-a")
    let o1 = p.parse(shlex"hey foo -a")
    check o1.argparse_command == "foo"
    check o1.command == "hey"
    
    check o1.foo == false # --foo flag
    check o1.argparse_foo_opts.isSome # foo command
    check o1.argparse_foo_opts.get.a == true
  
  test "flag named command":
    var p = newParser:
      flag("--command")
      command "foo":
        discard
    let opts = p.parse(shlex"foo")
    check opts.command == false
    check opts.argparse_command == "foo"
  
  test "option named command":
    var p = newParser:
      option("--command")
      command "foo":
        discard
    let opts = p.parse(shlex"foo")
    check opts.command == ""
    check opts.argparse_command == "foo"
  
  test "arg named command":
    var p = newParser:
      arg("command")
      command "foo":
        discard
    let opts = p.parse(shlex"hey foo")
    check opts.command == "hey"
    check opts.argparse_command == "foo"
  
  test "flag/command name conflict":
    var p = newParser:
      flag("--foo")
      command "foo": discard
    let opts = p.parse(shlex"foo")
    check opts.command == "foo"
    check opts.foo == false
    check opts.argparse_foo_opts.isSome
  
  test "option/command name conflict":
    var p = newParser:
      option("--foo")
      command "foo": discard
    let opts = p.parse(shlex"foo")
    check opts.command == "foo"
    check opts.foo == ""
    check opts.argparse_foo_opts.isSome
  
  test "command with hyphen":
    var p = newParser:
      command "some-command": discard
    let opts = p.parse(shlex"some-command")
    check opts.command == "some-command"
    check opts.argparse_some_command_opts.isSome
  
  test "arg/command name conflict":
    var p = newParser:
      arg("foo")
      command "foo": discard
    let opts = p.parse(shlex"hey foo")
    check opts.command == "foo"
    check opts.foo == "hey"
    check opts.argparse_foo_opts.isSome
  

suite "misc":
  test "README run":
    var res:seq[string]
    var p = newParser:
      flag("-a", "--apple")
      flag("-b", help="Show a banana")
      option("-o", "--output", help="Output to this file")
      command("somecommand"):
        arg("name")
        arg("others", nargs = -1)
        run:
          res.add opts.name
          res.add opts.others
          res.add $opts.parentOpts.apple
          res.add $opts.parentOpts.b
          res.add opts.parentOpts.output

    p.run(@["--apple", "-o=foo", "somecommand", "myname", "thing1", "thing2"])
    check res == @[
      "myname",
      "thing1",
      "thing2",
      "true",
      "false",
      "foo",
    ]
  
  test "README parse":
    var p = newParser:
      flag("-a", "--apple")
      flag("-b", help="Show a banana")
      option("-o", "--output", help="Output to this file")
      arg("name")
      arg("others", nargs = -1)

    var opts = p.parse(@["--apple", "-o=foo", "hi"])
    assert opts.apple == true
    assert opts.b == false
    assert opts.output == "foo"
    assert opts.name == "hi"
    assert opts.others == @[]
  
  test "parse with no args":
    let tmpfile = currentSourcePath().parentDir() / "something.nim"
    defer:
      removeFile(tmpfile)
      removeFile(tmpfile.changeFileExt(ExeExt))
    tmpfile.writeFile("""
import argparse
var p = newParser:
  arg("name")

echo p.parse().name
    """)
    let output = execProcess(findExe"nim",
      args = ["c", "--hints:off", "--verbosity:0", "-r", tmpfile, "bob"],
      options = {})
    checkpoint "=============== output =============="
    checkpoint output
    checkpoint "====================================="
    check output == "bob\n"
  
  test "std/logging":
    let tmpfile = currentSourcePath().parentDir() / "std_logging.nim"
    defer:
      removeFile(tmpfile)
      removeFile(tmpfile.changeFileExt(ExeExt))
    tmpfile.writeFile("""
import std/logging, argparse
addHandler newConsoleLogger()
error "ok"
var p = newParser:
  arg("foo")
    """)
    let output = execProcess(findExe"nim",
      args = ["c", "--hints:off", "--verbosity:0", "-r", tmpfile],
      options = {poStdErrToStdOut})
    checkpoint "=============== output =============="
    checkpoint output
    checkpoint "====================================="
    check "ERROR ok" in output

import macros
import argparse
# import macros
import os
# import parseopt
import sequtils
import streams
import strformat
import strutils
import unittest

proc shlex(x:string):seq[string] =
  # XXX this is not accurate, but okay enough for testing
  if x == "":
    result = @[]
  else:
    result = x.split({' '})

template withEnv(name:string, value:string, body:untyped):untyped =
  let old_value = getEnv(name, "")
  putEnv(name, value)
  body
  putEnv(name, old_value)

suite "flags":
  test "short flags":
    var p = newParser "some name":
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
      flag("-c", multiple=true)
    
    check "Some apples" in p.help
    check "More help" in p.help
  
  test "unknown flag":
    var p = newParser:
      flag("-a")
    expect UsageError:
      discard p.parse(shlex"-b")


suite "options":
  test "short options":
    var p = newParser:
      option("-a", help="Stuff")
    check p.parse(shlex"-a=5").a == "5"
    check p.parse(shlex"-a 5").a == "5"

    check "Stuff" in p.help
  
  test "long options":
    var p = newParser:
      option("--apple")
    check p.parse(shlex"--apple=10").apple == "10"
    check p.parse(shlex"--apple 10").apple == "10"
  
  test "option default":
    var p = newParser:
      option("--category", default=some("pinball"))
    check p.parse(shlex"").category == "pinball"
    check p.parse(shlex"--category foo").category == "foo"
  
  test "option default from env var":
    var p = newParser:
      option("--category", env="HELLO", default=some("who"))
    check "HELLO" in p.help
    check p.parse(shlex"").category == "who"
    withEnv("HELLO", "Adele"):
      check p.parse(shlex"").category == "Adele"
    check p.parse(shlex"--category hey").category == "hey"
  
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
    p.run(shlex"-h", quitOnShortCircuit = false, output = op)
    op.setPosition(0)
    var output = op.readAll()
    check "--foo" in output
    check "Top level help" in output

    op = newStringStream("")
    p.run(shlex"something --help", quitOnShortCircuit = false, output = op)
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
      p.run(shlex"-h", quitOnShortCircuit = false)
    
    expect UsageError:
      p.run(shlex"something --help", quitOnShortCircuit = false)
  
  test "parse help":
    let
      p = newParser: discard
    let opts = p.parse(@["-h"])
    check opts.help == true

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


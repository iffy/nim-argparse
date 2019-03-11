
import macros
import unittest
import argparse
import strutils
import strformat
import parseopt

proc shlex(x:string):seq[string] =
  # XXX this is not accurate, but okay enough for testing
  if x == "":
    result = @[]
  else:
    result = x.split({' '})

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
    var p = newParser("some name"):
      flag("--apple")
      flag("--banana")
    
    check p.parse(shlex"--apple").apple == true
    check p.parse(shlex"--apple").banana == false
    check p.parse(shlex"--banana").banana == true
    check "some name" in p.help
    check "--apple" in p.help
    check "--banana" in p.help
  
  test "short and long flags":
    var p = newParser("some name"):
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
    var p = newParser("hi"):
      flag("-b", multiple=true)
    
    check p.parse(shlex("-b")).b == 1
    check p.parse(shlex("-b -b")).b == 2
    check p.parse(shlex("")).b == 0
  
  test "help text":
    var p = newParser("some name"):
      flag("-a", "--apple", help="Some apples")
      flag("--banana-split-and-ice-cream", help="More help")
      flag("-c", multiple=true)
    
    check "Some apples" in p.help
    check "More help" in p.help
  
  test "unknown flag":
    var p = newParser("prog"):
      flag("-a")
    expect UsageError:
      discard p.parse(shlex"-b")


suite "options":
  test "short options":
    var p = newParser("some name"):
      option("-a", help="Stuff")
    check p.parse(shlex"-a=5").a == "5"
    check p.parse(shlex"-a 5").a == "5"

    check "Stuff" in p.help
  
  test "long options":
    var p = newParser("some name"):
      option("--apple")
    check p.parse(shlex"--apple=10").apple == "10"
    check p.parse(shlex"--apple 10").apple == "10"
  
  test "option default":
    var p = newParser("options"):
      option("--category", default="pinball")
    check p.parse(shlex"").category == "pinball"
    check p.parse(shlex"--category foo").category == "foo"
  
  test "unknown option":
    var p = newParser("prog"):
      option("-a")
    expect UsageError:
      discard p.parse(shlex"-b")
  
  test "multiple options":
    var p = newParser("hey"):
      option("-a", multiple=true)
    check p.parse(shlex"-a 10 -a 20").a == @["10", "20"]
    check p.parse(shlex"").a == []
    check p.parse(shlex"-a 20").a == @["20"]
  
  test "choices":
    var p = newParser("choiceprog"):
      option("-b", choices = @["first", "second", "third"])

    check p.parse(shlex"-b first").b == "first"
    expect UsageError:
      discard p.parse(shlex"-b unknown")
  
  test "choices multiple":
    var p = newParser("choiceprog"):
      option("-b", multiple=true, choices = @["first", "second", "third"])

    check p.parse(shlex"-b first").b == @["first"]
    check p.parse(shlex"-b first -b second").b == @["first", "second"]

suite "args":
  test "single, required arg":
    var p = newParser("prog"):
      arg("name")
    check p.parse(shlex"foo").name == "foo"
    check "name" in p.help
  
  test "single arg with default":
    var p = newParser("prog"):
      arg("name", default="foo")
    check p.parse(shlex"").name == "foo"
    check p.parse(shlex"something").name == "something"
  
  test "2 args":
    var p = newParser("prog"):
      arg("name")
      arg("age")
    check p.parse(shlex"foo bar").name == "foo"
    check p.parse(shlex"foo bar").age == "bar"
    check "name" in p.help
    check "age" in p.help
  
  test "arg help":
    var p = newParser("prog"):
      arg("name", help="Something")
    check "Something" in p.help
  
  test "nargs=2":
    var p = newParser("prog"):
      arg("name", nargs=2)
    check p.parse(shlex"a b").name == @["a", "b"]
  
  test "nargs=-1":
    var p = newParser("prog"):
      arg("thing", nargs = -1)
    check p.parse(shlex"").thing.len == 0
    check p.parse(shlex"a").thing == @["a"]
    check p.parse(shlex"a b c").thing == @["a", "b", "c"]

  test "nargs=-1 at the end":
    var p = newParser("prog"):
      arg("first")
      arg("thing", nargs = -1)
    check p.parse(shlex"first").thing.len == 0
    check p.parse(shlex"first a").thing == @["a"]
    check p.parse(shlex"first a b c").thing == @["a", "b", "c"]
  
  test "nargs=-1 in the middle":
    var p = newParser("prog"):
      arg("first")
      arg("thing", nargs = -1)
      arg("last")
    check p.parse(shlex"first last").thing.len == 0
    check p.parse(shlex"first a last").thing == @["a"]
    check p.parse(shlex"first a b c last").thing == @["a", "b", "c"]
  
  test "nargs=-1 at the beginning":
    var p = newParser("prog"):
      flag("-a")
      arg("thing", nargs = -1)
      arg("last", nargs = 2)
    check p.parse(shlex"last 2").thing.len == 0
    check p.parse(shlex"a last 2").thing == @["a"]
    check p.parse(shlex"a b c last 2").thing == @["a", "b", "c"]
    check p.parse(shlex"last 2").last == @["last", "2"]

  test "nargs=-1 nargs=2 nargs=2":
    var p = newParser("prog"):
      arg("first", nargs = -1)
      arg("middle", nargs = 2)
      arg("last", nargs = 2)
    check p.parse(shlex"a b c d").first.len == 0
    check p.parse(shlex"a b c d").middle == @["a", "b"]
    check p.parse(shlex"a b c d").last == @["c", "d"]
  
  test "nargs=-1 nargs=1 w/ default":
    var p = newParser("prog"):
      arg("first", nargs = -1)
      arg("last", default="hey")
    check p.parse(shlex"").last == "hey"
    check p.parse(shlex"hoo").last == "hoo"
    check p.parse(shlex"a b goo").last == "goo"

suite "autohelp":
  test "helpbydefault":
    var res:string
    var p = newParser("helptest"):
      run:
        res.add("main ran")
      command("something"):
        run:
          res.add("sub ran")
    
    p.run(shlex"-h", quitOnHelp = false)
    p.run(shlex"something --help", quitOnHelp = false)
    check res == ""
  
  test "nohelpflag":
    var res:string
    var p = newParser("helptest"):
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
      p = newParser("helptest"): discard
      opts = p.parse(@["-h"])
    check opts.help == true

suite "commands":
  test "run":
    var res:string = "hello"

    var p = newParser("prog"):
      command "command1":
        help("Some help text")
        flag("-a")
        run:
          echo "executing command1"
          res = $opts.a

    p.run(shlex"command1 -a")
    check res == "true"
    p.run(shlex"command1")
    check res == "false"
  
  test "two commands":
    var res:string = ""

    var p = newParser("My Program"):
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

    var p = newParser("Nested"):
      option("-a")
      command "sub":
        option("-a")
        run:
          res = &"{opts.parentOpts.a},{opts.a}" 
    
    p.run(shlex"-a parent sub -a child")
    check res == "parent,child"
  
  test "unknown command":
    var res:string = ""

    var p = newParser("prog"):
      command "sub":
        option("-a")
        run:
          res = "did run"
    expect UsageError:
      discard p.parse(shlex"madeupcommand")
    
    check res == ""


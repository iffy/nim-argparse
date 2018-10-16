
import macros
import unittest
import argparse
import strutils
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
  
  test "help text":
    var p = newParser("some name"):
      flag("-a", "--apple", help="Some apples")
      flag("--banana-split-and-ice-cream", help="More help")
    
    check "Some apples" in p.help
    check "More help" in p.help

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

suite "args":
  test "single, required arg":
    var p = newParser("prog"):
      arg("name")
    check p.parse(shlex"foo").name == "foo"
    check "name" in p.help
  
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

suite "commands":
  test "run":
    var res:string

    var p = newParser("prog"):
      command "command1":
        help("Some help text")
        flag("-a")
        run:
          echo "inside actual run proc"
          # res = $opts.a
    
    echo p.help

    p.run(shlex"command1 -a")
    check res == "true"
    p.run(shlex"command1")
    check res == "false"


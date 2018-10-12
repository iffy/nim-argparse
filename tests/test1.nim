
import macros
import unittest
import argparse
import strutils
import parseopt

suite "flags":
  test "short flags":
    var p = newParser("some name"):
      flag("-a")
      flag("-b")
    
    check p.parse("-a").a == true
    check p.parse("-a").b == false
    check "some name" in p.help
    check "-a" in p.help
    check "-b" in p.help
  
  test "long flags":
    var p = newParser("some name"):
      flag("--apple")
      flag("--banana")
    
    check p.parse("--apple").apple == true
    check p.parse("--apple").banana == false
    check p.parse("--banana").banana == true
    check "some name" in p.help
    check "--apple" in p.help
    check "--banana" in p.help
  
  test "short and long flags":
    var p = newParser("some name"):
      flag("-a", "--apple")
      flag("--banana", "-b")
    
    check p.parse("--apple").apple == true
    check p.parse("--apple").banana == false
    check p.parse("-b").banana == true
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
    check p.parse("-a=5").a == "5"
    # check p.parse("-a 5").a == "5"
    check p.parse("-a:5").a == "5"

    check "Stuff" in p.help
  
  test "long options":
    var p = newParser("some name"):
      option("--apple")
    check p.parse("--apple=10").apple == "10"
    # check p.parse("--apple 10").apple == "10"
    check p.parse("--apple:10").apple == "10"

suite "args":
  test "single, required arg":
    var p = newParser("prog"):
      arg("name")
    check p.parse("foo").name == "foo"
    check "name" in p.help
  
  test "2 args":
    var p = newParser("prog"):
      arg("name")
      arg("age")
    check p.parse("foo bar").name == "foo"
    check p.parse("foo bar").age == "bar"
    check "name" in p.help
    check "age" in p.help
  
  test "arg help":
    var p = newParser("prog"):
      arg("name", help="Something")
    check "Something" in p.help
    echo p.help

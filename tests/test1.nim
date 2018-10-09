
import macros
import unittest
import argparse
import strutils


dumpTree:
  type
    Foo = object
      a*: bool

suite "flags":
  test "simplest short option":
    macro makeParser(): untyped =
      mkParser("some name"):
        flag("-a")
        flag("-b")
    var p = makeParser()
    
    echo p.help
    check p.parse("-a").a == true
    check p.parse("-a").b == false
    check false == true
    check "some name" in p.help
    check "-a" in p.help
    check "-b" in p.help
  
  # test "long options":
  #   macro makeParser(): untyped =
  #     mkParser("some name"):
  #       flag("--apple", "-a")
  #       flag("-b", "--banana")
  #       flag("--cat")
  #   var p = makeParser()
    
  #   echo p.help
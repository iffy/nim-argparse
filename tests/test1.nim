
import macros
import unittest
import argparse
import strutils
import parseopt

suite "flags":
  test "short flags":
    macro makeParser(): untyped =
      mkParser("some name"):
        flag("-a")
        flag("-b")
    var p = makeParser()
    
    check p.parse("-a").a == true
    check p.parse("-a").b == false
    check "some name" in p.help
    check "-a" in p.help
    check "-b" in p.help
  
  test "long flags":
    macro makeParser(): untyped =
      mkParser("some name"):
        flag("--apple")
        flag("--banana")
    var p = makeParser()
    
    check p.parse("--apple").apple == true
    check p.parse("--apple").banana == false
    check p.parse("--banana").banana == true
    check "some name" in p.help
    check "--apple" in p.help
    check "--banana" in p.help
  
  test "short and long flags":
    macro makeParser(): untyped =
      mkParser("some name"):
        flag("-a", "--apple")
        flag("--banana", "-b")
    var p = makeParser()
    
    check p.parse("--apple").apple == true
    check p.parse("--apple").banana == false
    check p.parse("-b").banana == true
    check "some name" in p.help
    check "--apple" in p.help
    check "-a" in p.help
    check "--banana" in p.help
    check "-b" in p.help

import macros
import unittest
import argparse
import strutils
import parseopt

suite "flags":
  test "simplest short option":
    macro makeParser(): untyped =
      mkParser("some name"):
        flag("-a")
        flag("-b")
    var p = makeParser()
    
    echo "Help is: ", p.help
    check p.parse("-a").a == true
    check p.parse("-a").b == false
    check "some name" in p.help
    check "-a" in p.help
    check "-b" in p.help

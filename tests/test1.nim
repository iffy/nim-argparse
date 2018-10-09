
import macros
import unittest
import argparse
import strutils

dumpTree:
  discard 5

suite "flags":
  test "simplest short option":
    var p = mkParser("some name"):
      flag("-a")
    
    check "-a" in p.help
    check "some name" in p.help
    check p.parse("-a").a == true

  # test "long option":
  #   var p = mkParser:
  #     flag("--foo")

  #   check p.parse("--foo").foo == true
  
  # test "long and short":
  #   var p = mkParser:
  #     flag("-f", "--foo")

  #   check p.parse("-f").foo == true
  #   check p.parse("--foo").foo == true

  # test "help":
  #   var p = mkParser:
  #     flag("-f", help="hello")

  #   let helptext = p.renderHelp()
  #   check "hello" in helptext

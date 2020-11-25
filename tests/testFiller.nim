import unittest
import argparse/filler

# R = required
# Rn = required, width n
# O = optional
# W = wildcard

proc ch(filler: ref ArgFiller, nargs: int): string =
  ## Get a string representation of how the args will be distributed
  for channel in filler.channels(nargs):
    for i in channel.idx:
      result.add(channel.dest)

test "R":
  var filler = newArgFiller()
  filler.required("a")
  check filler.minArgs == 1
  check filler.ch(1) == "a"
  check filler.missing(0) == @["a"]

test "R2":
  var filler = newArgFiller()
  filler.required("a", 2)
  check filler.minArgs == 2
  check filler.ch(2) == "aa"
  check filler.missing(0) == @["a", "a"]

test "RR":
  var filler = newArgFiller()
  filler.required("a")
  filler.required("b")
  check filler.minArgs == 2
  check filler.ch(2) == "ab"
  check filler.missing(0) == @["a", "b"]

test "O":
  var filler = newArgFiller()
  filler.optional("a")
  check filler.minArgs == 0
  check filler.ch(0) == ""
  check filler.ch(1) == "a"
  check filler.missing(0).len == 0

test "OO":
  var filler = newArgFiller()
  filler.optional("a")
  filler.optional("b")
  check filler.minArgs == 0
  check filler.ch(0) == ""
  check filler.ch(1) == "a"
  check filler.ch(2) == "ab"
  check filler.missing(0).len == 0

test "ROO":
  var filler = newArgFiller()
  filler.required("a")
  filler.optional("b")
  filler.optional("c")
  check filler.minArgs == 1
  check filler.ch(1) == "a"
  check filler.ch(2) == "ab"
  check filler.ch(3) == "abc"
  check filler.missing(0) == @["a"]

test "ORO":
  var filler = newArgFiller()
  filler.optional("a")
  filler.required("b")
  filler.optional("c")
  check filler.minArgs == 1
  check filler.ch(1) == "b"
  check filler.ch(2) == "ab"
  check filler.ch(3) == "abc"
  check filler.missing(0) == @["b"]

test "OORROO":
  var filler = newArgFiller()
  filler.optional("a")
  filler.optional("b")
  filler.required("c")
  filler.required("d")
  filler.optional("e")
  filler.optional("f")
  check filler.minArgs == 2
  check filler.ch(2) == "cd"
  check filler.ch(3) == "acd"
  check filler.ch(4) == "abcd"
  check filler.ch(5) == "abcde"
  check filler.ch(6) == "abcdef"
  check filler.missing(0) == @["c", "d"]
  check filler.missing(1) == @["d"]

test "OOROROO":
  var filler = newArgFiller()
  filler.optional("a")
  filler.optional("b")
  filler.required("c")
  filler.optional("d")
  filler.required("e")
  filler.optional("f")
  filler.optional("g")
  check filler.minArgs == 2
  check filler.ch(2) == "ce"
  check filler.ch(3) == "ace"
  check filler.ch(4) == "abce"
  check filler.ch(5) == "abcde"
  check filler.ch(6) == "abcdef"
  check filler.ch(7) == "abcdefg"
  check filler.missing(0) == @["c", "e"]
  check filler.missing(1) == @["e"]

test "OOR":
  var filler = newArgFiller()
  filler.optional("a")
  filler.optional("b")
  filler.required("c")
  check filler.minArgs == 1
  check filler.ch(1) == "c"
  check filler.ch(2) == "ac"
  check filler.ch(3) == "abc"
  check filler.missing(0) == @["c"]

test "W":
  var filler = newArgFiller()
  filler.wildcard("a")
  check filler.minArgs == 0
  check filler.ch(0) == ""
  check filler.ch(1) == "a"
  check filler.ch(2) == "aa"
  check filler.ch(3) == "aaa"
  check filler.missing(0).len == 0

test "WR":
  var filler = newArgFiller()
  filler.wildcard("a")
  filler.required("b")
  check filler.minArgs == 1
  check filler.ch(1) == "b"
  check filler.ch(2) == "ab"
  check filler.ch(3) == "aab"
  check filler.missing(0) == @["b"]

test "RW":
  var filler = newArgFiller()
  filler.required("a")
  filler.wildcard("b")
  check filler.minArgs == 1
  check filler.ch(1) == "a"
  check filler.ch(2) == "ab"
  check filler.ch(3) == "abb"
  check filler.missing(0) == @["a"]

test "RWR":
  var filler = newArgFiller()
  filler.required("a")
  filler.wildcard("b")
  filler.required("c")
  check filler.minArgs == 2
  check filler.ch(2) == "ac"
  check filler.ch(3) == "abc"
  check filler.ch(4) == "abbc"
  check filler.missing(0) == @["a", "c"]
  check filler.missing(1) == @["c"]

test "WW":
  var filler = newArgFiller()
  filler.wildcard("a")
  expect Exception:
    filler.wildcard("b")

test "WO":
  var filler = newArgFiller()
  filler.wildcard("a")
  filler.optional("b")
  check filler.minArgs == 0
  check filler.ch(0) == ""
  check filler.ch(1) == "b"
  check filler.ch(2) == "ab"
  check filler.ch(3) == "aab"

test "OW":
  var filler = newArgFiller()
  filler.optional("a")
  filler.wildcard("b")
  check filler.minArgs == 0
  check filler.ch(0) == ""
  check filler.ch(1) == "a"
  check filler.ch(2) == "ab"
  check filler.ch(3) == "abb"

test "ROWOR":
  var filler = newArgFiller()
  filler.required("a")
  filler.optional("b")
  filler.wildcard("c")
  filler.optional("d")
  filler.required("e")
  check filler.minArgs == 2
  check filler.ch(2) == "ae"
  check filler.ch(3) == "abe"
  check filler.ch(4) == "abde"
  check filler.ch(5) == "abcde"
  check filler.ch(6) == "abccde"
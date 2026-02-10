import unittest
import argparse/[backend,types]

suite "ParseState":
  
  test "basic":
    var state = newParseState(["-a", "hi"])
    check state.cursor == 0
    check state.token.get() == "-a"
    check state.key.get() == "-a"
    check state.value.get() == "hi"
  
  test "= separator":
    var state = newParseState(["-a=foo"])
    check state.token.get() == "-a=foo"
    check state.key.get() == "-a"
    check state.value.get() == "foo"
  
  test "- value":
    var state = newParseState(["-a=-b"])
    check state.token.get() == "-a=-b"
    check state.key.get() == "-a"
    check state.value.get() == "-b"
  
  test "- value space":
    var state = newParseState(["-a", "-b"])
    check state.token.get() == "-a"
    check state.key.get() == "-a"
    check state.value.get() == "-b"
  
  test "consume flag":
    var state = newParseState(["-a", "hi"])
    state.consume(ArgFlag)
    check state.cursor == 1
    check state.token.get() == "hi"
    check state.key.isSome()
    check state.key.get() == "hi"
    check state.value.isNone()
    check state.extra.len == 0
    
    state.consume(ArgFlag)
    check state.cursor == 2
    check state.done == true
    check state.key.isNone()
    check state.value.isNone()
    check state.token.isNone()
    check state.extra.len == 0
  
  test "consume option":
    var state = newParseState(["-a", "hi"])
    state.consume(ArgOption)
    check state.cursor == 2
    check state.done == true
    check state.key.isNone()
    check state.value.isNone()
    check state.token.isNone()
    check state.extra.len == 0
  
  test "consume arg":
    var state = newParseState(["-a", "hi"])
    state.consume(ArgArgument)
    check state.cursor == 1
    check state.done == false
    check state.key.isSome()
    check state.value.isNone()
    check state.token.get() == "hi"
    check state.key.get() == "hi"
    check state.extra.len == 0

  test "skip flag":
    var state = newParseState(["-a", "hi"])
    state.skip()
    check state.cursor == 1
    check state.extra == @["-a"]
    state.skip()
    check state.cursor == 2
    check state.extra == @["-a", "hi"]
    check state.done == true

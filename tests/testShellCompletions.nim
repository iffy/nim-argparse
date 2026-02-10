import std/[unittest,envvars,strformat,osproc]
import argparse, argparse/shellcompletion/[shellcompletion,fish]
import ./util


template checkAndFish(conditon: untyped, msg: string): untyped =
  check conditon, msg
  
test "Print":
  var o = newStringStream()
  var p = newParser("mycmd"):
    flag("-a")

  # no completions printed by default
  p.run(shlex "-a", output=o)
  o.setPosition(0)
  check o.atEnd() or not o.readLine().contains(COMPLETION_HEADER[0 ..^ 2])
  
  # # print completions with short flag
  o = newStringStream()
  p.run(shlex "-"&COMPLETION_SHORT_FLAG, output = o)
  o.setPosition(0)
  check o.readLine().contains(COMPLETION_HEADER[0 ..^ 2])

  # print completions with long flag + shell
  o = newStringStream()
  p.run(shlex "--" & COMPLETION_LONG_FLAG & " fish", output = o)
  o.setPosition(0)
  check o.readLine().contains(COMPLETION_HEADER[0 ..^ 2])
  
suite "Help":
  test "Completion option help":
    var p = newParser("a"):
      flag("-a")
    var o = newStringStream()
    p.run(shlex"-h", quitOnHelp = false, output = o)
    o.setPosition(0)
    var mout = o.readAll()
    check "--" & COMPLETION_LONG_FLAG in mout
  test "Completion flag help":
    var p = newParser("a"):
      flag("-a")
    var o = newStringStream()
    p.run(shlex"-h", quitOnHelp = false, output = o)
    o.setPosition(0)
    var mout = o.readAll()
    check COMPLETION_SHORT_HELP in mout
suite "Disable":
  test "Completion disable":
    var q = newParser("b"):
      noCompletions()
      flag("-b")
    var r = newStringStream()
    q.run(shlex"-h", quitOnHelp = false, output = r)
    var mout = r.readAll()
    check "--" & COMPLETION_LONG_FLAG notin mout
    check COMPLETION_SHORT_HELP notin mout
    
    expect UsageError:
      q.run(shlex"-c")
    expect UsageError:
      q.run(shlex "--" & COMPLETION_LONG_FLAG & " fish")
      
  test "Disable completion option leave flag":
    var p = newParser("a"):
      flag("-a")
      # without short
      noCompletions(disableFlag=false)
    var o = newStringStream()
    p.run(shlex"-h", quitOnHelp = false, output = o)
    o.setPosition(0)
    var mout = o.readAll()
    check "--" & COMPLETION_LONG_FLAG notin mout
    check COMPLETION_SHORT_HELP in mout
    
    expect UsageError:
      p.run(shlex "--" & COMPLETION_LONG_FLAG & " fish", quitOnHelp = false)
      
    o = newStringStream()  
    p.run(shlex "-" & COMPLETION_SHORT_FLAG, output=o)
    o.setPosition(0)
    check COMPLETION_HEADER[0..^2] in o.readAll()
    
  test "Disable completion flag leave option":
    var q = newParser("b"):
      flag("-b")
      # without long
      noCompletions(disableOpt=false)
    var o = newStringStream()
    q.run(shlex"-h", quitOnHelp = false, output = o)
    o.setPosition(0)
    var mout = o.readAll()
    check "--" & COMPLETION_LONG_FLAG in mout
    check COMPLETION_SHORT_HELP notin mout
    
    expect UsageError: # short flag not present
      q.run(shlex "-" & COMPLETION_SHORT_FLAG)
      
    o = newStringStream()
    q.run(shlex "--" & COMPLETION_LONG_FLAG & " fish", output = o)  
    o.setPosition(0)
    check COMPLETION_HEADER[0..^2] in o.readAll()
suite "Environment":
  test "Shell from environment":
    putenv("SHELL", "/usr/bin/fish")
    var p= newParser("mycmd"):
      flag("-a")
    var o = newStringStream()
    p.run(shlex "-" & COMPLETION_SHORT_FLAG, output = o)
    o.setPosition(0)
    check o.readall().split("\n").contains(COMPLETION_HEADER_FISH[0..^2])
      
    putEnv("SHELL", "/usr/bin/ush")
    var q = newParser("mycmd"):
      flag("-a")
    expect UsageError:
      q.run(shlex "-" & COMPLETION_SHORT_FLAG, output = o)
  test "Option overrides environment":
    putenv("SHELL", "/usr/bin/ush")
    var p = newParser("mycmd"):
      flag("-a")
    var o = newStringStream()
    p.run(shlex "--" & COMPLETION_LONG_FLAG & " fish", output = o)
    o.setPosition(0)
    check o.readall().split("\n").contains(COMPLETION_HEADER_FISH[0..^2])
    
suite "Hide":
  test "Hide completions from help":
    var p = newParser("mycmd"):
      flag("-a")
      hideCompletions()
    var o = newStringStream()
    p.run(shlex"-h", quitOnHelp = false, output = o)
    o.setPosition(0)
    var mout = o.readAll()
    check "--" & COMPLETION_LONG_FLAG notin mout
    check COMPLETION_SHORT_HELP notin mout
    
suite "Completion generators":
  test "Any directory in pwd":
    const completionsGenerator: array[ShellCompletionKind,string] = [
      sckFish: "__fish_complete_directories"
    ]
    const pidsGenerator: array[ShellCompletionKind,string] = [
      sckFish: "ps -eo pid= | awk '{print $1}'"
    ]
    var p = newParser("mycmd"):
      arg("dir", help="a directory", completionsGenerator=completionsGenerator)
      option("--opt", help="an option", completionsGenerator=pidsGenerator)
    var o = newStringStream()
    p.run(shlex "--" & COMPLETION_LONG_FLAG & " fish", output = o)
    o.setPosition(0)
    var completions: string = o.readAll()
    check completions.contains("__fish_complete_directories")
    check completions.contains("ps -eo pid= | awk '{print $1}'")
    
    
suite "Validity":
  for shell in COMPLETION_SHELLS:
    test &"{shell} shell":
      if findExe(shell) == "":
        skip()
      else:
        var p = newParser("mycmd"):
          flag("-a", help="an option")
          option("--opt", help="an option with argument")
          arg("files", help="input files")
        var o = newStringStream()
        p.run(shlex "--" & COMPLETION_LONG_FLAG & " " & shell, output = o)
        o.setPosition(0)
        var completions: string = o.readAll()
        var outEx =  execCmdEx(&"{shell} -c \"source /dev/stdin\"", input=completions)
        check outEx.exitCode == 0
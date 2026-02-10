import std/[strutils]
proc shlex*(x:string):seq[string] =
  # XXX this is not accurate, but okay enough for testing
  if x == "":
    result = @[]
  else:
    result = x.split({' '})

template withEnv*(name:string, value:string, body:untyped):untyped =
  let old_value = getEnv(name, "")
  putEnv(name, value)
  body
  putEnv(name, old_value)

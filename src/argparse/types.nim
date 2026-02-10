import std/[options]
type
  UsageError* = object of ValueError
  
  ShortCircuit* = object of CatchableError
    flag*: string
    help*: string
    
  ShellCompletionKind* = enum
    sckFish = "fish"
    #sckBash = "bash" not implemented
    #sckZsh = "zsh" not implemented
    
  ComponentKind* = enum
    ArgFlag
    ArgOption
    ArgArgument
  
  Component* = object
    varname*: string
    hidden*: bool
    help*: string
    env*: string
    case kind*: ComponentKind
    of ArgFlag:
      flagShort*: string
      flagLong*: string
      flagMultiple*: bool
      shortCircuit*: bool
    of ArgOption:
      optShort*: string
      optLong*: string
      optMultiple*: bool
      optDefault*: Option[string]
      optChoices*: seq[string]
      optCompletionsGenerator*: array[ShellCompletionKind, string]
      optRequired*: bool
    of ArgArgument:
      nargs*: int
      argDefault*: Option[string]
      argCompletionsGenerator*: array[ShellCompletionKind, string]

  Builder* = ref BuilderObj
  BuilderObj* {.acyclic.} = object
    ## A compile-time object used to accumulate parser options
    ## before building the parser
    name*: string
      ## Command name for subcommand parsers, or program name for
      ## the parent parser.
    symbol*: string
      ## Unique tag to apply to Parser and Option types to avoid
      ## conflicts.  By default, this is generated with Nim's
      ## gensym algorithm.
    components*: seq[Component]
    help*: string
    groupName*: string
    children*: seq[Builder]
    parent*: Option[Builder]
    runProcBodies*: seq[NimNode]
 
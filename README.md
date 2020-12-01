# argparse

![tests](https://github.com/iffy/nim-argparse/workflows/tests/badge.svg?branch=master)

Command line argument parsing library.  It generates the parser at compile time so that parsed options have a well-defined type.

# Example

After defining your expected arguments with `newParser(...)`, use:

1. `run(...)` to parse and execute any `run:` blocks you've defined.  This will automatically display help text when `-h`/`--help` is used.
2. `parse(...)` to parse without executing, giving you more control over what happens.

Both procs will parse the process' command line if no arguments are given.

[See the docs for more info](https://www.iffycan.com/nim-argparse/argparse.html)

## run()

```nim
import argparse

var p = newParser:
  flag("-a", "--apple")
  flag("-b", help="Show a banana")
  option("-o", "--output", help="Output to this file")
  command("somecommand"):
    arg("name")
    arg("others", nargs = -1)
    run:
      echo opts.name
      echo opts.others
      echo opts.parentOpts.apple
      echo opts.parentOpts.b
      echo opts.parentOpts.output

try:
  p.run(@["--apple", "-o=foo", "somecommand", "myname", "thing1", "thing2"])
except UsageError as e:
  stderr.writeLine getCurrentExceptionMsg()
  quit(1)
```

## parse()

```nim
import argparse

var p = newParser:
  flag("-a", "--apple")
  flag("-b", help="Show a banana")
  option("-o", "--output", help="Output to this file")
  arg("name")
  arg("others", nargs = -1)

try:
  var opts = p.parse(@["--apple", "-o=foo", "hi"])
  assert opts.apple == true
  assert opts.b == false
  assert opts.output == "foo"
  assert opts.name == "hi"
  assert opts.others == @[]
except ShortCircuit as e:
  if e.flag == "argparse_help":
    echo p.help
    quit(1)
except UsageError:
  stderr.writeLine getCurrentExceptionMsg()
  quit(1)
```

# Development

## Running tests

Run tests with:

```
nimble test
```

Run a single test with:

```
nim c -r tests/test1.nim -g "somepatternmatchingthetestname"
```

## Building the docs

When you publish a new version, publish the docs by running `./builddocs.sh` then pushing `master`.
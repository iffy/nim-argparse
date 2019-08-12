# argparse

[![Build Status](https://travis-ci.org/iffy/nim-argparse.svg?branch=master)](https://travis-ci.org/iffy/nim-argparse)

Command line argument parsing library.  It generates the parser at compile time so that parsed options have a well-defined type.

# Example

After defining your expected arguments with `newParser(...)`, use:

1. `run(...)` to parse and execute any `run:` blocks you've defined.  This will automatically display help text when `-h`/`--help` is used.
2. `parse(...)` to parse without executing.

Both procs will parse the process' command line if no arguments are given.

[See the docs for more info](https://www.iffycan.com/nim-argparse/argparse.html)

## run()

```nim
import argparse

var p = newParser("My Program"):
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

p.run(@["--apple", "-o=foo", "somecommand", "myname", "thing1", "thing2"])
```

## parse()

```nim
import argparse

var p = newParser("My Program"):
  flag("-a", "--apple")
  flag("-b", help="Show a banana")
  option("-o", "--output", help="Output to this file")
  arg("name")
  arg("others", nargs = -1)

var opts = p.parse(@["--apple", "-o=foo", "hi"])
assert opts.apple == true
assert opts.b == false
assert opts.output == "foo"
assert opts.name == "hi"
assert opts.others == @[]
```

# TODO

- [X] --long-flags
- [X] --arguments=withvalues
- [X] help argument
- [X] arguments
- [X] variable args
- [X] sub commands (git-style)
- [X] sub commands access parent opts
- [X] render docs
- [X] --help special case
- [ ] --version
- [X] default values
- [X] raise exception on invalid args
- [X] Handle `--arg val --nother-arg val2` (spaces instead of `=` or `:` between key and value)
- [ ] Access to object type names (so you can do `handleOpts(opts: TheGeneratedType) = ...`)
- [X] Make it so you don't have to use a wrapping macro
- [ ] parse strings into sequences (shlex-like)
- [X] fail on unknown arguments
- [X] let options have a list of acceptable values (choices)


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

When you publish a new version, publish the docs by running `make` then pushing `master`.
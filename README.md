# argparse

[![Build Status](https://travis-ci.org/iffy/nim-argparse.svg?branch=master)](https://travis-ci.org/iffy/nim-argparse)

WIP command line argument parsing library.  It generates the parser at compile time so that the object returned by `parse` has a well-defined type.

# Example

```nim
import argparse

var p = newParser("My Program"):
  flag("-a", "--apple")
  flag("-b", help="Show a banana")
  option("-o", "--output", help="Output to this file")
  arg("name")
  arg("others", nargs=-1)

var opts = p.parse(@["--apple", "-o=foo", "hi"])
assert opts.apple == true
assert opts.b == false
assert opts.output == "foo"
assert opts.name == "hi"
assert opts.others == @[]

echo p.help
```

[See the docs for more info](https://www.iffycan.com/nim-argparse/argparse.html)

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


## Running tests

Run tests with:

```
nimble test
```

Run a single test with:

```
nim c -r tests/test1.nim -g "somepatternmatchingthetestname"
```

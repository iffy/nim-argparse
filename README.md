# argparse

WIP command line argument parsing library.  It generates the parser at compile time so that the object returned by `parse` has a well-defined type.

# Usage

Define an argument parser with `newParser`:

```nim
import argparse

var p = newParser("My Program"):
  flag("-a", "--apple")
  flag("-b", help="Show a banana")
  option("-o", "--output", help="Output to this file")

assert p.parse("-a").apple == true
assert p.parse("-b").b == true
assert p.parse("--apple").b == false
assert p.parse("--apple").apple == true
assert p.parse("-o=foo").output == "foo"

echo p.help
```


# TODO

- [X] --long-flags
- [X] --arguments=withvalues
- [X] help argument
- [ ] --help special case
- [ ] --version
- [ ] raise exception on invalid args
- [ ] Handle `--arg val --nother-arg val2` (spaces instead of `=` or `:` between key and value)
- [ ] sub commands (git-style)
- [ ] arguments
- [ ] variable args
- [ ] Access to object types (so you can do `handleOpts(opts: TheGeneratedType) = ...`)
- [X] Make it so you don't have to use a wrapping macro

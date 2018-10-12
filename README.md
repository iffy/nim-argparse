# argparse

WIP command line argument parsing library.  It generates the parser at compile time so that the object returned by `parse` has a well-defined type.

For full usage, see the [tests/](./tests/)

```nim
import argparse

macro makeParser(): untyped =
  mkParser("My Program"):
    flag("-a", "--apple")
    flag("-b")
var p = makeParser()

assert p.parse("-a").apple == true
assert p.parse("-b").b == true
assert p.parse("--apple")).b == false
assert p.parse("--apple")).apple == true
```


# TODO

- [X] --long-flags
- [ ] Access to object types (so you can do `handleOpts(opts: TheGeneratedType) = ...`)
- [ ] Make it so you don't have to use a wrapping macro
- [ ] --arguments=withvalues
- [ ] sub commands (git-style)

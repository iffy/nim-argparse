# argparse

WIP argument command line argument parsing library.  It generates the parser at compile time so that the object returned by `parse` has a well-defined type.

For full usage, see the [tests/](./tests/)

```nim
import argparse

macro makeParser(): untyped =
  mkParser("My Program"):
    flag("-a")
    flag("-b")
var p = makeParser()

assert p.parse("-a").a == true
assert p.parse("-b").b == true
assert p.parse("-a)).b == false
```


# TODO

- [ ] --long-opts
- [ ] Access to object types (so you can do `handleOpts(opts: TheGeneratedType) = ...`)
- [ ] --arguments=withvalues
- [ ] sub commands (git-style)

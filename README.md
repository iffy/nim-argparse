# argparse

WIP command line argument parsing library.  It generates the parser at compile time so that the object returned by `parse` has a well-defined type.

# Usage

Define an argument parser with `newParser` then use it to parse command line arguments.  If you call `parse` without any arguments, it will parse the arguments passed in to the program.

```nim
import argparse

var p = newParser("My Program"):
  flag("-a", "--apple")
  flag("-b", help="Show a banana")
  option("-o", "--output", help="Output to this file")
  arg("name")
  arg("others", nargs=-1)

assert p.parse(@["-a", "hi"]).apple == true
assert p.parse(@["-b", "hi"]).b == true
assert p.parse(@["--apple", "hi"]).b == false
assert p.parse(@["--apple", "hi"]).apple == true
assert p.parse(@["-o=foo", "hi"]).output == "foo"
assert p.parse(@["hi"]).name == "hi"
assert p.parse(@["hi", "my", "friends"]).others == @["my", "friends"]

echo p.help
```

You can run subcommands

```nim
import argparse

var p = newParser("My Program"):
  command "move":
    arg("howmuch")
    run:
      echo "moving", opts.howmuch
  command "eat":
    arg("what")
    run:
      echo "you ate ", opts.what

p.run(@["move", "10"])
p.run(@["eat", "apple"])
```


# TODO

- [X] --long-flags
- [X] --arguments=withvalues
- [X] help argument
- [X] arguments
- [X] variable args
- [ ] sub commands (git-style)
- [ ] --help special case
- [ ] --version
- [ ] default values
- [ ] raise exception on invalid args
- [ ] Handle `--arg val --nother-arg val2` (spaces instead of `=` or `:` between key and value)
- [ ] Access to object types (so you can do `handleOpts(opts: TheGeneratedType) = ...`)
- [X] Make it so you don't have to use a wrapping macro

# v2.0.1 - 2021-07-13

- **FIX:** Removed program name from default subcommand help text
- **FIX:** Restore ability to call `parse()` without args ([#64](https://github.com/iffy/nim-argparse/issues/64))

# v2.0.0 - 2020-12-03

- **BREAKING CHANGE:** Calling `parse()` with `-h`/`--help` flags will now raise a `ShortCircuit` error instead of returning options with the `.help` attribute set.
- **NEW:** Removed `argparse_help` and other shortcircuiting flags from the parser options object since they are no longer accessible anyway.
- **NEW:** You can now access subcommand options with `parse()`. ([#60](https://github.com/iffy/nim-argparse/issues/60))
- **FIX:** Required options no longer override `-h`/`--help` shortcircuitry ([#57](https://github.com/iffy/nim-argparse/issues/57))
- **FIX:** Fix parsing of options that combine key and value into a single command-line token.

# v1.1.0 - 2020-11-28

- **NEW:** You can now use `--` to stop further flag/option parsing so that remaining command line parameters are considered arguments.
- **NEW:** It's easy now to have the argument help text display the runtime name of the application using the special `{prog}` string within help text.  To get the new runtime name behavior, call `newParser` without a string name. (Fixes [#33](https://github.com/iffy/nim-argparse/issues/33))
- **NEW:** Options can now be marked as required. ([#31](https://github.com/iffy/nim-argparse/issues/31))
- **FIX:** Works with Nim 1.0.x again.
- **FIX:** Support hidden args again.
- **FIX:** Add documentation and examples back.

# v1.0.0 - 2020-11-26

- **BREAKING CHANGE:** Default values for `option()` and `arg()` are now given as `Option` types.
- **BREAKING CHANGE:** argparse no longer compiles on 1.0.x versions of Nim
- **NEW:** Added a changelog!
- **FIX:** Better error thrown when an option is lacking a value ([#29](https://github.com/iffy/nim-argparse/issues/29))
- **FIX:** Better error for when args are missing ([#18](https://github.com/iffy/nim-argparse/issues/18))
- **FIX:** You can now pass `-` as a value to args and options ([#40](https://github.com/iffy/nim-argparse/issues/40))

# v0.10.1

- No changelog data prior to this.

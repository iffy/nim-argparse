It's easy now to have the argument help text display the runtime name of the application using the special `{prog}` string within help text.  To get the new runtime name behavior, call `newParser` without a string name. (Fixes [#33](https://github.com/iffy/nim-argparse/issues/33))
# Package

version       = "4.1.2"
author        = "Matt Haggard"
description   = "A command line argument parser"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.2.18" # tested through to 2.2.6 via choosenim

import std/[sequtils,strutils,strformat]
# nimble builddocs
task builddocs, "Builds the documentation using Nim's docgen":
  exec "rm -rf docs/*"
  # --outdir is bugged and not working
  var cmd = &"""
    nim \
      --colors:on \
      --path:$projectDir \
      --docInternal \
      --project \
      --index:on \
      --outdir:docs \
      doc \
        src/argparse.nim
  """
  discard gorgeEx cmd
  # first pass for the index
  var result = gorgeEx cmd
  if result.exitCode != 0:
    echo "Documentation generation had some errors;"
    # lines with "Error" in them
    echo ""
    echo result.output.splitLines().filterIt(it.contains "Error").join("\n")

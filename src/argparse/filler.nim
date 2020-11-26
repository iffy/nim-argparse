import tables

type
  SlotKind* = enum
    Required
    Optional
    Wildcard

  Slot = object
    name: string
    case kind*: SlotKind
    of Required:
      nargs: int
    else:
      discard

  ArgFiller* = object
    slots: seq[Slot]
    counts: CountTableRef[SlotKind]

  FillChannel* = tuple
    idx: Slice[int]
    dest: string
    kind: SlotKind

proc newArgFiller*(): ref ArgFiller =
  new(result)
  result.counts = newCountTable[SlotKind]()

using
  filler: ref ArgFiller

proc required*(filler; argname: string, nargs = 1) =
  filler.slots.add(Slot(kind: Required, name: argname, nargs: nargs))
  filler.counts.inc(Required, nargs)

proc optional*(filler; argname: string) =
  filler.slots.add(Slot(kind: Optional, name: argname))
  filler.counts.inc(Optional)

proc wildcard*(filler; argname: string) =
  if filler.counts[Wildcard] > 0:
    raise ValueError.newException("More than one wildcard argument not allowed")
  filler.slots.add(Slot(kind: Wildcard, name: argname))
  filler.counts.inc(Wildcard)

proc minArgs*(filler): int =
  for slot in filler.slots:
    if slot.kind == Required:
      result.inc(slot.nargs)

proc numArgsAfterWildcard*(filler): int =
  var afterWildcard = false
  for slot in filler.slots:
    if slot.kind == Wildcard:
      afterWildcard = true
    elif afterWildcard:
      case slot.kind
      of Required:
        result.inc(slot.nargs)
      of Optional:
        result.inc(1)
      of Wildcard:
        discard

proc hasVariableArgs*(filler): bool =
  filler.counts[Optional] > 0 or filler.counts[Wildcard] > 0

proc hasWildcard*(filler): bool =
  filler.counts[Wildcard] > 0

proc upperBreakpoint*(filler): int =
  filler.counts[Required] + filler.counts[Optional] + filler.counts[Wildcard]

proc channels*(filler; nargs: int): seq[FillChannel] =
  ## Given the number of arguments, show where those arguments will go
  var toget = newCountTable[SlotKind]()
  var left = nargs
  for kind in [Required, Optional, Wildcard]:
    var kind_left = filler.counts[kind]
    let totake = min(kind_left, left)
    if totake > 0:
      left.dec(totake)
      kind_left.dec(totake)
      toget.inc(kind, totake)
  var idx = 0
  for slot in filler.slots:
    if toget[slot.kind] > 0:
      case slot.kind
      of Required:
        result.add (idx..(idx+slot.nargs - 1), slot.name, slot.kind)
      of Optional:
        result.add (idx..idx, slot.name, slot.kind)
      of Wildcard:
        result.add (idx..(idx + left), slot.name, slot.kind)
      {.push assertions: off.}
      toget[slot.kind] = max(toget[slot.kind] - result[^1][0].len, 0)
      {.pop.}
      idx.inc(result[^1][0].len)

proc missing*(filler; nargs: int): seq[string] =
  ## Given the number of arguments, which required arguments will
  ## not get a value?
  var left = nargs
  for slot in filler.slots:
    if slot.kind == Required:
      for c in 0..<slot.nargs:
        left.dec()
        if left < 0:
          result.add slot.name

proc generate*(filler; containerName: string): NimNode =
  discard

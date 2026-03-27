## `dump` hooks for stdlib types

import ./[common, flat_basic], std/[options, sets, tables, json]

proc dump*(format: static GrimeDumpFormat, writer: var GrimeDumper, v: JsonNode) =
  if v == nil:
    # consider same as null i guess
    writer.writeByte byte(JNull)
  else:
    writer.writeByte byte(v.kind)
    case v.kind:
    of JObject:
      format.dump(writer, v.len)
      for k, e in v.pairs:
        format.dump(writer, k)
        format.dump(writer, e)
    of JArray:
      format.dump(writer, v.len)
      for e in v:
        format.dump(writer, e)
    of JNull:
      discard
    of JInt:
      format.dump(writer, v.num)
    of JFloat:
      format.dump(writer, v.fnum)
    of JString:
      format.dump(writer, v.strVal)
    of JBool:
      format.dump(writer, v.bval)

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var JsonNode) =
  var kind: JsonNodeKind
  read(format, reader, kind)
  v = JsonNode(kind: kind)
  case kind
  of JObject:
    var len: typeof(v.len)
    format.read(reader, len)
    v.fields = initOrderedTable[string, JsonNode](len)
    for _ in 0 ..< len:
      var k: string
      format.read(reader, k)
      var e: JsonNode
      format.read(reader, e)
      v.fields[k] = e
  of JArray:
    var len: typeof(v.len)
    format.read(reader, len)
    v.elems = newSeq[JsonNode](len)
    for e in v.elems.mitems:
      format.read(reader, e)
  of JNull:
    discard
  of JInt:
    format.read(reader, v.num)
  of JFloat:
    format.read(reader, v.fnum)
  of JString:
    format.read(reader, v.str)
  of JBool:
    format.read(reader, v.bval)

proc dump*[T](format: static GrimeDumpFormat, writer: var GrimeDumper, v: Option[T]) =
  mixin dump
  if v.isNone:
    writer.writeByte 0
  else:
    writer.writeByte 1
    format.dump(writer, v.get())

proc read*[T](format: static GrimeReadFormat, reader: var GrimeReader, v: var Option[T]) =
  mixin read
  var exists: bool
  read(format, reader, exists)
  if exists:
    var val: T
    read(format, reader, val)
    v = some(val)
  else:
    v = none(T)

proc dump*[T](format: static GrimeDumpFormat, writer: var GrimeDumper, v: HashSet[T]) =
  mixin dump
  format.dump(writer, v.len)
  for e in v:
    format.dump(writer, e)

proc dump*[T](format: static GrimeDumpFormat, writer: var GrimeDumper, v: OrderedSet[T]) =
  mixin dump
  format.dump(writer, v.len)
  for e in v:
    format.dump(writer, e)

proc read*[T](format: static GrimeReadFormat, reader: var GrimeReader, v: var HashSet[T]) =
  mixin read
  var len: typeof(v.len)
  read(format, reader, len)
  v = initHashSet[T](len)
  for _ in 0 ..< len:
    var val: T
    read(format, reader, val)
    v.incl(val)

proc read*[T](format: static GrimeReadFormat, reader: var GrimeReader, v: var OrderedSet[T]) =
  mixin read
  var len: typeof(v.len)
  read(format, reader, len)
  v = initOrderedSet[T](len)
  for _ in 0 ..< len:
    var val: T
    read(format, reader, val)
    v.incl(val)

template dumpTableImpl(format, writer, tab, K, V) =
  mixin dump
  when tab is ref:
    if isNil(tab):
      # consider same as empty i guess
      format.dump(writer, 0)
      return
  format.dump(writer, tab.len)
  for k, v in tab:
    format.dump writer, k
    format.dump writer, v

proc dump*[K, V](format: static GrimeDumpFormat, writer: var GrimeDumper, tab: Table[K, V]) =
  dumpTableImpl(format, writer, tab, K, V)

proc dump*[K, V](format: static GrimeDumpFormat, writer: var GrimeDumper, tab: OrderedTable[K, V]) =
  dumpTableImpl(format, writer, tab, K, V)

proc dump*[K](format: static GrimeDumpFormat, writer: var GrimeDumper, tab: CountTable[K]) =
  dumpTableImpl(format, writer, tab, K, int)

proc read*[K, V](format: static GrimeReadFormat, reader: var GrimeReader, tab: var Table[K, V]) =
  mixin read
  var len: typeof(tab.len)
  format.read(reader, len)
  tab = initTable[K, V](len)
  for _ in 0 ..< len:
    var k: K
    format.read reader, k
    var v: V
    format.read reader, v
    tab[k] = v

proc read*[K, V](format: static GrimeReadFormat, reader: var GrimeReader, tab: var OrderedTable[K, V]) =
  mixin read
  var len: typeof(tab.len)
  format.read(reader, len)
  tab = initOrderedTable[K, V](len)
  for _ in 0 ..< len:
    var k: K
    format.read reader, k
    var v: V
    format.read reader, v
    tab[k] = v

proc read*[K](format: static GrimeReadFormat, reader: var GrimeReader, tab: var CountTable[K]) =
  mixin read
  var len: typeof(tab.len)
  format.read(reader, len)
  tab = initCountTable[K](len)
  for _ in 0 ..< len:
    var k: K
    format.read reader, k
    var v: int
    format.read reader, v
    tab[k] = v

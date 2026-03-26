## implements dumping behavior for basic types 

import ./common, holo_flow/[holo_reader, holo_writer], std/typetraits

export HoloWriter, initHoloWriter, startWrite, finishWrite, write

when not (defined(js) or defined(nimscript)):
  import std/endians

template jsOrVm(a, b): untyped =
  when nimvm:
    block:
      a
  else:
    when defined(js) or defined(nimscript):
      a
    else:
      b

proc writeByte*(writer: var HoloWriter, b: byte) {.inline.} =
  writer.write char(b)

proc writeBytes*(writer: var HoloWriter, bs: openArray[byte]) {.inline.} =
  when declared(toOpenArrayChar): # >= 2.2
    writer.write bs.toOpenArrayChar(0, bs.len - 1)
  else:
    for b in bs:
      writer.addToBuffer(byte(b))
    writer.consumeBuffer()

proc endError*(reader: var HoloReader, expected: string) {.inline.} =
  raise newException(GrimeReadError, "expected " & expected & " but end reached")

template readByteInto[T](v: var T, expected: string) =
  when format.skip:
    if hasNext(reader):
      reader.unsafeNext()
    else:
      reader.endError(expected)
  else:
    jsOrVm:
      var c: char
      if peek(reader, c):
        reader.unsafeNext()
      else:
        reader.endError(expected)
      v = T(c)
    do:
      if peek(reader, cast[ptr char](addr v)[]):
        reader.unsafeNext()
      else:
        reader.endError(expected)

when false:
  proc readBytesInto(reader: var HoloReader, bs: var openArray[byte], expected: string) {.inline.} =
    when format.skip:
      if reader.hasNext(offset = bs.len - 1):
        reader.unsafeNextBy(bs.len)
      else:
        reader.endError(expected)
    elif declared(toOpenArrayChar): # >= 2.2
      if reader.peek(bs.toOpenArrayChar(0, bs.len - 1)):
        reader.unsafeNextBy(bs.len)
      else:
        reader.endError(expected)
    else:
      var cs = newString(bs.len)
      if reader.peek(cs):
        reader.unsafeNextBy(bs.len)
      else:
        reader.endError(expected)
      for i in 0 ..< cs.len:
        bs[i] = cs[i]

# all the read implementations depend on the dump implementation

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: byte) {.inline.} =
  writer.writeByte v

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var byte) {.inline.} =
  readByteInto(v, "byte")

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: bool) {.inline.} =
  writer.writeByte byte(v)

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var bool) {.inline.} =
  readByteInto(v, "bool")

template dumpRawBytesImpl() =
  when sizeof(v) == 1:
    writer.writeByte cast[byte](v)
  elif format.endian == cpuEndian:
    writer.writeBytes cast[ptr UncheckedArray[byte]](unsafeAddr v).toOpenArray(0, sizeof(v) - 1)
  else:
    var bytes: array[sizeof(v), byte]
    when sizeof(v) == 8:
      swapEndian64(addr bytes, unsafeAddr v)
    elif sizeof(v) == 4:
      swapEndian32(addr bytes, unsafeAddr v)
    elif sizeof(v) == 2:
      swapEndian16(addr bytes, unsafeAddr v)
    else:
      let srcBytes = cast[ptr UncheckedArray[byte]](unsafeAddr v)
      for i in 0 ..< sizeof(v):
        bytes[i] = srcBytes[sizeof(v) - i]
    writer.writeBytes bytes

template readRawBytesImpl(expected: string) =
  when format.skip:
    when sizeof(v) == 1:
      if reader.hasNext():
        reader.unsafeNext()
      else:
        reader.endError(expected)
    else:
      if reader.hasNext(offset = sizeof(v) - 1):
        reader.unsafeNextBy(sizeof(v))
      else:
        reader.endError(expected)
  elif sizeof(v) == 1:
    if reader.peek(cast[ptr char](unsafeAddr v)[]):
      reader.unsafeNext()
    else:
      reader.endError(expected)
  elif format.endian == cpuEndian:
    if reader.peek(cast[ptr array[sizeof(v), char]](unsafeAddr v)[]):
      reader.unsafeNextBy(sizeof(v))
    else:
      reader.endError(expected)
  else:
    var bytes: array[sizeof(v), char]
    if reader.peek(bytes):
      reader.unsafeNextBy(sizeof(v))
    else:
      reader.endError(expected)
    when sizeof(v) == 8:
      swapEndian64(unsafeAddr v, addr bytes)
    elif sizeof(v) == 4:
      swapEndian32(unsafeAddr v, addr bytes)
    elif sizeof(v) == 2:
      swapEndian16(unsafeAddr v, addr bytes)
    else:
      let destBytes = cast[ptr UncheckedArray[byte]](unsafeAddr v)
      for i in 0 ..< sizeof(v):
        destBytes[i] = bytes[sizeof(v) - i]

template dumpUintImpl() =
  jsOrVm:
    var bytes: array[sizeof(v), byte]
    var v2 = v
    for i in 0 ..< sizeof(v):
      # abysmal code style:
      bytes[
        when format.endian == littleEndian:
          i
        else:
          sizeof(v) - i - 1
      ] = byte(v2 and 0xFF)
      v2 = v2 shr 8
    writer.writeBytes bytes
  do:
    dumpRawBytesImpl()

template readUintImpl() =
  jsOrVm:
    var bytes: array[sizeof(v), char]
    if reader.peek(bytes):
      reader.unsafeNextBy(sizeof(v))
    else:
      reader.endError($typeof(v))
    v = 0
    for i in 0 ..< sizeof(v):
      # abysmal code style:
      v = (v shl 8) or typeof(v)(bytes[
        when format.endian == littleEndian:
          sizeof(v) - i - 1
        else:
          i
      ])
  do:
    readRawBytesImpl($typeof(v))

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: uint) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var uint) {.inline.} =
  readUintImpl()

# uint8 implemented at the start as byte

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: uint16) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var uint16) {.inline.} =
  readUintImpl()

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: uint32) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var uint32) {.inline.} =
  readUintImpl()

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: uint64) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var uint64) {.inline.} =
  readUintImpl()

# int/uint casts should work on js with --jsbigint64:on
template dumpIntImpl(uintType) =
  dump(format, writer, cast[uintType](v))
template readIntImpl(uintType) =
  jsOrVm:
    var impl: uintType
    read(format, reader, impl)
    v = cast[typeof(v)](impl)
  do:
    read(format, reader, cast[ptr uintType](unsafeAddr v)[])

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: int) {.inline.} =
  dumpIntImpl uint

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var int) {.inline.} =
  readIntImpl uint

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: int8) {.inline.} =
  writer.writeByte cast[byte](v)

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var int8) {.inline.} =
  readIntImpl uint8

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: int16) {.inline.} =
  dumpIntImpl uint16

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var int16) {.inline.} =
  readIntImpl uint16

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: int32) {.inline.} =
  dumpIntImpl uint32

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var int32) {.inline.} =
  readIntImpl uint32

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: int64) {.inline.} =
  dumpIntImpl uint64

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var int64) {.inline.} =
  readIntImpl uint64

# on js, uint64 is a bigint with jsbigint64:on, but casting uint64 to/from float does not work for infinity/nan

const grimeJsFloatUseDataView* {.booldefine.} = true

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: float) =
  when nimvm:
    dump(format, writer, cast[uint64](v))
  else:
    when defined(js):
      var u: uint64
      when grimeJsFloatUseDataView:
        {.emit: """
        var view = new DataView(new ArrayBuffer(8));
        view.setFloat64(0, `v`);
        `u` = view.getBigUint64(0);
        """.}
      else:
        {.emit: """
        var buffer = new ArrayBuffer(8);
        var intView = new BigUint64Array(buffer);
        var floatView = new Float64Array(buffer);
        floatView[0] = `v`;
        `u` = intView[0];
        """.}
      dump(format, writer, u)
    else:
      dump(format, writer, cast[uint64](v))

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var float) {.inline.} =
  when nimvm:
    block:
      var impl: uint64
      read(format, reader, impl)
      v = cast[float](impl)
  else:
    when defined(js):
      var u: uint64
      read(format, reader, u)
      var f: float
      when grimeJsFloatUseDataView:
        {.emit: """
        var view = new DataView(new ArrayBuffer(8));
        view.setBigUint64(0, `u`);
        `f` = view.getFloat64(0);
        """.}
      else:
        {.emit: """
        var buffer = new ArrayBuffer(8);
        var intView = new BigUint64Array(buffer);
        var floatView = new Float64Array(buffer);
        intView[0] = `u`;
        `f` = floatView[0];
        """.}
      v = f
    elif defined(nimscript):
      var impl: uint64
      read(format, reader, impl)
      v = cast[float](impl)
    else:
      read(format, reader, cast[ptr uint64](unsafeAddr v)[])

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: float32) =
  when nimvm:
    dump(format, writer, cast[uint32](v))
  else:
    when defined(js):
      var u: uint32
      when grimeJsFloatUseDataView:
        {.emit: """
        var view = new DataView(new ArrayBuffer(8));
        view.setFloat32(0, `v`);
        `u` = view.getUint32(0);
        """.}
      else:
        {.emit: """
        var buffer = new ArrayBuffer(4);
        var intView = new Uint32Array(buffer);
        var floatView = new Float32Array(buffer);
        floatView[0] = `v`;
        `u` = intView[0];
        """.}
      dump(format, writer, u)
    else:
      dump(format, writer, cast[uint32](v))

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var float32) {.inline.} =
  when nimvm:
    block:
      var impl: uint32
      read(format, reader, impl)
      v = cast[float32](impl)
  else:
    when defined(js):
      var u: uint32
      read(format, reader, u)
      var f: float32
      when grimeJsFloatUseDataView:
        {.emit: """
        var view = new DataView(new ArrayBuffer(8));
        view.setUint32(0, `u`);
        `f` = view.getFloat32(0);
        """.}
      else:
        {.emit: """
        var buffer = new ArrayBuffer(4);
        var intView = new Uint32Array(buffer);
        var floatView = new Float32Array(buffer);
        intView[0] = `u`;
        `f` = floatView[0];
        """.}
      v = f
    elif defined(nimscript):
      var impl: uint32
      read(format, reader, impl)
      v = cast[float32](impl)
    else:
      read(format, reader, cast[ptr uint32](unsafeAddr v)[])

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: string) =
  # force 4 bytes? use some weird utf8-like dynamic bytes for the length?
  dump(format, writer, v.len)
  # ignores endian
  writer.write v

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var string) =
  var len: typeof(v.len)
  read(format, reader, len)
  v = newString(len)
  if reader.peek(v):
    reader.unsafeNextBy(len)
  else:
    reader.endError("string of len " & $len)

proc dump*(format: static GrimeDumpFormat, writer: var HoloWriter, v: char) {.inline.} =
  writer.write v

proc read*(format: static GrimeReadFormat, reader: var HoloReader, v: var char) =
  if reader.peek(v):
    reader.unsafeNext()
  else:
    reader.endError("char")

proc dump*[T: tuple | object](format: static GrimeDumpFormat, writer: var HoloWriter, v: T) =
  mixin dump
  # XXX depends on `fields` iterator order https://github.com/holo-nim/holo-map/issues/11
  for e in v.fields:
    format.dump(writer, e)

proc read*[T: tuple | object](format: static GrimeReadFormat, reader: var HoloReader, v: var T) =
  mixin read
  for e in v.fields:
    when T is object:
      {.cast(uncheckedAssign).}:
        read(format, reader, e)
    else:
      read(format, reader, e)

proc dump*[T: enum](format: static GrimeDumpFormat, writer: var HoloWriter, v: T) {.inline.} =
  when sizeof(v) == 8:
    dumpIntImpl(uint64)
  elif sizeof(v) == 4:
    dumpIntImpl(uint32)
  elif sizeof(v) == 2:
    dumpIntImpl(uint16)
  elif sizeof(v) == 1:
    writer.writeByte cast[byte](v)
  else:
    {.error: "unexpected size for enum " & $T & ": " & $sizeof(T).}

proc read*[T: enum](format: static GrimeReadFormat, reader: var HoloReader, v: var T) =
  when sizeof(v) == 8:
    readIntImpl(uint64)
  elif sizeof(v) == 4:
    readIntImpl(uint32)
  elif sizeof(v) == 2:
    readIntImpl(uint16)
  elif sizeof(v) == 1:
    readIntImpl(uint8)
  else:
    {.error: "unexpected size for enum " & $T & ": " & $sizeof(T).}

proc dump*[N, T](format: static GrimeDumpFormat, writer: var HoloWriter, v: array[N, T]) =
  mixin dump
  # does not write length
  # can only override with distinct type?
  for e in v:
    format.dump(writer, e)

proc read*[N, T](format: static GrimeReadFormat, reader: var HoloReader, v: var array[N, T]) =
  mixin read
  for e in v.mitems:
    format.read(reader, e)

proc dump*[T](format: static GrimeDumpFormat, writer: var HoloWriter, v: seq[T]) =
  mixin dump
  # force 4 bytes? use some weird utf8-like dynamic bytes for the length?
  dump(format, writer, v.len)
  for e in v:
    format.dump(writer, e)

proc read*[T](format: static GrimeReadFormat, reader: var HoloReader, v: var seq[T]) =
  mixin read
  var len: typeof(v.len)
  read(format, reader, len)
  v = newSeq[T](len)
  for e in v.mitems:
    format.read(reader, e)

proc dump*[T](format: static GrimeDumpFormat, writer: var HoloWriter, v: set[T]) =
  dumpRawBytesImpl()

proc read*[T](format: static GrimeReadFormat, reader: var HoloReader, v: set[T]) =
  readRawBytesImpl("set of type " & $T)

proc dump*[T](format: static GrimeDumpFormat, writer: var HoloWriter, v: ref T) {.inline.} =
  ## handled as an "optional" type, first byte is 1 if exists and 0 if nil
  ## 
  ## warning: no reference semantics means this is prone to infinite recursion if there is a cycle
  # XXX maybe another format that allows reference semantics, would need a separate lookup table writer/state tracker
  mixin dump
  if v == nil:
    writer.writeByte 0
  else:
    writer.writeByte 1
    format.dump(writer, v[])

proc read*[T](format: static GrimeReadFormat, reader: var HoloReader, v: var ref T) =
  mixin read
  var exists: bool
  read(format, reader, exists)
  if exists:
    new(v)
    format.read(reader, v[])
  else:
    v = nil

proc dump*[T: distinct](format: static GrimeDumpFormat, writer: var HoloWriter, v: T) {.inline.} =
  mixin dump
  format.dump(writer, distinctBase(T)(v))

proc read*[T: distinct](format: static GrimeReadFormat, reader: var HoloReader, v: var T) {.inline.} =
  mixin read
  format.read(reader, distinctBase(T)(v))

proc dump*[T](format: static GrimeDumpFormat, s: var string, v: T) {.inline.} =
  mixin dump
  var writer = initHoloWriter()
  writer.startWrite()
  dump(format, writer, v)
  s = writer.finishWrite()

proc dumpGrime*[T](writer: var HoloWriter, v: T) {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(), writer, v)

proc dumpGrime*[T](s: var string, v: T) {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(), s, v)

proc read*[T](format: static GrimeReadFormat, reader: var HoloReader, _: typedesc[T]): T =
  mixin read
  read(format, reader, result)

proc readGrime*[T](reader: var HoloReader, v: var T) {.inline.} =
  mixin read
  read(GrimeReadFormat(), reader, v)

proc readGrime*[T](reader: var HoloReader, _: typedesc[T]): T {.inline.} =
  mixin read
  read(GrimeReadFormat(), reader, result)

proc toGrime*[T](v: T): string {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(), result, v)

template toStaticGrime*(v: untyped): static[string] =
  ## This will turn v into json at compile time and return the json string.
  const s = v.toGrime()
  s

proc fromGrime*[T](s: string, x: typedesc[T], format: static GrimeReadFormat = GrimeReadFormat()): T {.inline.} =
  mixin read
  result = default(T)
  var reader = initHoloReader(doLineColumn = false) # XXX byte offset instead of line column
  reader.startRead(s)
  read(format, reader, result)
  if reader.hasNext():
    var msg = "extra character after reading grime: "
    msg.addQuoted(reader.peekOrZero())
    raise newException(GrimeReadError, msg)

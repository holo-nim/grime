## implements dumping behavior for basic types 

import ./[common, dict], holo_flow/[load_reader, flush_writer], std/typetraits

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

proc writeByte*(writer: var FlushWriter, b: byte) {.inline.} =
  writer.write char(b)

proc writeBytes*(writer: var FlushWriter, bs: openArray[byte]) {.inline.} =
  when declared(toOpenArrayChar): # >= 2.2
    writer.write bs.toOpenArrayChar(0, bs.len - 1)
  else:
    for b in bs:
      writer.addToBuffer(byte(b))
    writer.consumeBuffer()

proc endError*(reader: var LoadReader, expected: string) {.inline.} =
  raise newException(GrimeReadError, "expected " & expected & " but end reached")

template readByteInto[T](v: var T, expected: string) =
  when format.skip:
    if hasNext(reader.data):
      reader.data.unsafeNext()
    else:
      reader.data.endError(expected)
  else:
    jsOrVm:
      var c: char
      if peek(reader.data, c):
        reader.data.unsafeNext()
      else:
        reader.data.endError(expected)
      v = T(c)
    do:
      if peek(reader.data, cast[ptr char](addr v)[]):
        reader.data.unsafeNext()
      else:
        reader.data.endError(expected)

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

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: byte) {.inline.} =
  dumper.data.writeByte v

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var byte) {.inline.} =
  readByteInto(v, "byte")

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: bool) {.inline.} =
  dumper.data.writeByte byte(v)

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var bool) {.inline.} =
  readByteInto(v, "bool")

template dumpRawBytesImpl() =
  when sizeof(v) == 1:
    dumper.data.writeByte cast[byte](v)
  elif format.shared.endian == cpuEndian:
    dumper.data.writeBytes cast[ptr UncheckedArray[byte]](unsafeAddr v).toOpenArray(0, sizeof(v) - 1)
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
    dumper.data.writeBytes bytes

template readRawBytesImpl(expected: string) =
  when format.skip:
    when sizeof(v) == 1:
      if reader.data.hasNext():
        reader.data.unsafeNext()
      else:
        reader.data.endError(expected)
    else:
      if reader.data.hasNext(offset = sizeof(v) - 1):
        reader.data.unsafeNextBy(sizeof(v))
      else:
        reader.data.endError(expected)
  elif sizeof(v) == 1:
    if reader.data.peek(cast[ptr char](unsafeAddr v)[]):
      reader.data.unsafeNext()
    else:
      reader.data.endError(expected)
  elif format.shared.endian == cpuEndian:
    if reader.data.peek(cast[ptr array[sizeof(v), char]](unsafeAddr v)[]):
      reader.data.unsafeNextBy(sizeof(v))
    else:
      reader.data.endError(expected)
  else:
    var bytes: array[sizeof(v), char]
    if reader.data.peek(bytes):
      reader.data.unsafeNextBy(sizeof(v))
    else:
      reader.data.endError(expected)
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
        when format.shared.endian == littleEndian:
          i
        else:
          sizeof(v) - i - 1
      ] = byte(v2 and 0xFF)
      v2 = v2 shr 8
    dumper.data.writeBytes bytes
  do:
    dumpRawBytesImpl()

template readUintImpl() =
  jsOrVm:
    var bytes: array[sizeof(v), char]
    if reader.data.peek(bytes):
      reader.data.unsafeNextBy(sizeof(v))
    else:
      reader.data.endError($typeof(v))
    v = 0
    for i in 0 ..< sizeof(v):
      # abysmal code style:
      v = (v shl 8) or typeof(v)(bytes[
        when format.shared.endian == littleEndian:
          sizeof(v) - i - 1
        else:
          i
      ])
  do:
    readRawBytesImpl($typeof(v))

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: uint) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var uint) {.inline.} =
  readUintImpl()

# uint8 implemented at the start as byte

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: uint16) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var uint16) {.inline.} =
  readUintImpl()

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: uint32) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var uint32) {.inline.} =
  readUintImpl()

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: uint64) {.inline.} =
  dumpUintImpl()

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var uint64) {.inline.} =
  readUintImpl()

# int/uint casts should work on js with --jsbigint64:on
template dumpIntImpl(uintType) =
  dump(format, dumper, cast[uintType](v))
template readIntImpl(uintType) =
  jsOrVm:
    var impl: uintType
    read(format, reader, impl)
    v = cast[typeof(v)](impl)
  do:
    read(format, reader, cast[ptr uintType](unsafeAddr v)[])

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: int) {.inline.} =
  dumpIntImpl uint

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var int) {.inline.} =
  readIntImpl uint

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: int8) {.inline.} =
  dumper.data.writeByte cast[byte](v)

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var int8) {.inline.} =
  readIntImpl uint8

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: int16) {.inline.} =
  dumpIntImpl uint16

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var int16) {.inline.} =
  readIntImpl uint16

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: int32) {.inline.} =
  dumpIntImpl uint32

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var int32) {.inline.} =
  readIntImpl uint32

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: int64) {.inline.} =
  dumpIntImpl uint64

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var int64) {.inline.} =
  readIntImpl uint64

# on js, uint64 is a bigint with jsbigint64:on, but casting uint64 to/from float does not work for infinity/nan

const grimeJsFloatUseDataView* {.booldefine.} = true

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: float) =
  when nimvm:
    dump(format, dumper, cast[uint64](v))
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
      dump(format, dumper, u)
    else:
      dump(format, dumper, cast[uint64](v))

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var float) {.inline.} =
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

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: float32) =
  when nimvm:
    dump(format, dumper.data, cast[uint32](v))
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
      dump(format, dumper.data, u)
    else:
      dump(format, dumper.data, cast[uint32](v))

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var float32) {.inline.} =
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

template byteCount*[T: SomeNumber | enum | bool | char | set](format: static GrimeFormat, x: T): int = sizeof(T)

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: string) =
  # XXX force 4 bytes? use some weird utf8-like dynamic bytes for the length?
  dump(format, dumper, v.len)
  # ignores endian
  dumper.data.write v

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var string) =
  var len: typeof(v.len)
  read(format, reader, len)
  v = newString(len)
  if reader.data.peek(v):
    reader.data.unsafeNextBy(len)
  else:
    reader.data.endError("string of len " & $len)

proc byteCount*(format: static GrimeFormat, x: string): int {.inline.} =
  byteCount(format, x.len) + x.len

proc dump*(format: static GrimeDumpFormat, dumper: var GrimeDumper, v: char) {.inline.} =
  dumper.data.write v

proc read*(format: static GrimeReadFormat, reader: var GrimeReader, v: var char) =
  if reader.data.peek(v):
    reader.data.unsafeNext()
  else:
    reader.data.endError("char")

proc dump*[T: tuple | object](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: T) =
  mixin dump
  # XXX depends on `fields` iterator order https://github.com/holo-nim/holo-map/issues/11
  for e in v.fields:
    format.dump(dumper, e)

proc read*[T: tuple | object](format: static GrimeReadFormat, reader: var GrimeReader, v: var T) =
  mixin read
  for e in v.fields:
    when T is object:
      {.cast(uncheckedAssign).}:
        read(format, reader, e)
    else:
      read(format, reader, e)

proc byteCount*[T: tuple | object](format: static GrimeFormat, x: T): int =
  result = 0
  for e in x.fields:
    # for objects this branches for variants,
    # so we cannot use `len * byteCount` in collections
    result += byteCount(format, e)

proc dump*[T: enum](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: T) {.inline.} =
  when sizeof(v) == 8:
    dumpIntImpl(uint64)
  elif sizeof(v) == 4:
    dumpIntImpl(uint32)
  elif sizeof(v) == 2:
    dumpIntImpl(uint16)
  elif sizeof(v) == 1:
    dumper.data.writeByte cast[byte](v)
  else:
    {.error: "unexpected size for enum " & $T & ": " & $sizeof(T).}

proc read*[T: enum](format: static GrimeReadFormat, reader: var GrimeReader, v: var T) =
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

proc dump*[N, T](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: array[N, T]) =
  mixin dump
  # does not write length
  # can only override with distinct type?
  for e in v:
    format.dump(dumper, e)

proc read*[N, T](format: static GrimeReadFormat, reader: var GrimeReader, v: var array[N, T]) =
  mixin read
  for e in v.mitems:
    format.read(reader, e)

proc byteCount*[I, T](format: static GrimeFormat, x: array[I, T]): int =
  result = 0
  for e in x.items:
    result += byteCount(format, e)

proc dump*[T](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: seq[T]) =
  mixin dump
  # XXX force 4 bytes? use some weird utf8-like dynamic bytes for the length?
  dump(format, dumper, v.len)
  for e in v:
    format.dump(dumper, e)

proc read*[T](format: static GrimeReadFormat, reader: var GrimeReader, v: var seq[T]) =
  mixin read
  var len: typeof(v.len)
  read(format, reader, len)
  v = newSeq[T](len)
  for e in v.mitems:
    format.read(reader, e)

proc byteCount*[T](format: static GrimeFormat, x: seq[T]): int =
  result = 0
  for e in x.items:
    # compiler might optimize this if it doesnt branch
    result += byteCount(format, e)

proc dump*[T](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: set[T]) =
  dumpRawBytesImpl()

proc read*[T](format: static GrimeReadFormat, reader: var GrimeReader, v: set[T]) =
  readRawBytesImpl("set of type " & $T)

proc dump*[T: ref | ptr](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: T) {.inline.} =
  ## on flat mode, handled as an "optional" type, first byte is 1 if exists and 0 if nil
  ## on dict mode, data is saved to the dictionary and the final value is the dictionary index
  ## 
  ## warning: no reference semantics on flat mode means this is prone to infinite recursion if there is a cycle
  ## 
  ## also warning: VM does not have a way to get reference identity,
  ## and JS needs a global map to track it which can be disabled with `-d:grimeTrackJsDictReferences=false`,
  ## so dict mode cannot deal with cycles in those either
  mixin dump
  when format.shared.dict:
    dumpPointer(format, dumper, v)
  else:
    if v == nil:
      dumper.data.writeByte 0
    else:
      dumper.data.writeByte 1
      format.dump(dumper, v[])

proc read*[T: ref | ptr](format: static GrimeReadFormat, reader: var GrimeReader, v: var T) =
  mixin read
  when format.shared.dict:
    readPointer(format, reader, v)
  else:
    var exists: bool
    read(format, reader, exists)
    if exists:
      new(v)
      format.read(reader, v[])
    else:
      v = nil

proc byteCount*[T: ref | ptr](format: static GrimeFormat, x: T): int =
  when format.dict:
    result = dictByteCount(format, x)
  else:
    result = sizeof(bool)
    if not x.isNil:
      result += byteCount(x[])

proc dump*[T: distinct](format: static GrimeDumpFormat, dumper: var GrimeDumper, v: T) {.inline.} =
  mixin dump
  format.dump(dumper, distinctBase(T)(v))

proc read*[T: distinct](format: static GrimeReadFormat, reader: var GrimeReader, v: var T) {.inline.} =
  mixin read
  format.read(reader, distinctBase(T)(v))

template byteCount*[T: distinct](format: static GrimeFormat, x: T): int =
  byteCount(format, distinctBase(T)(x))

proc dump*[T](format: static GrimeDumpFormat, s: var string, v: T) {.inline.} =
  mixin dump
  var dumper = GrimeDumper(dict: initFlushWriter(), data: initFlushWriter())
  when format.shared.dict:
    dumper.dict.startWrite()
  dumper.data.startWrite()
  dump(format, dumper, v)
  when format.shared.dict:
    var writer = initFlushWriter()
    writer.startWrite()
    merge(GrimeMergeFormat(inner: format), writer, dumper)
    s = writer.finishWrite()
  else:
    s = dumper.data.finishWrite()

proc dumpFlatGrime*[T](s: var string, v: T) {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(shared: GrimeFormat(dict: false)), s, v)

proc dumpDictGrime*[T](s: var string, v: T) {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(shared: GrimeFormat(dict: true)), s, v)

proc toFlatGrime*[T](v: T): string {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(shared: GrimeFormat(dict: false)), result, v)

proc toDictGrime*[T](v: T): string {.inline.} =
  mixin dump
  dump(GrimeDumpFormat(shared: GrimeFormat(dict: true)), result, v)

proc read*[T](format: static GrimeReadFormat, reader: var GrimeReader, _: typedesc[T]): T =
  mixin read
  read(format, reader, result)

proc fromGrime*[T](s: string, x: typedesc[T], format: static GrimeReadFormat): T {.inline.} =
  mixin read
  result = default(T)
  var reader = GrimeReader(data: initLoadReader())
  when format.shared.dict:
    var data = initLoadReader(doLineColumn = false) # XXX byte offset instead of line column
    data.startRead(s)
    split(GrimeSplitFormat(inner: format), data, reader)
    read(format, reader, result)
  else:
    reader.data = initLoadReader(doLineColumn = false) # XXX byte offset instead of line column
    reader.data.startRead(s)
    read(format, reader, result)
  if reader.data.hasNext():
    var msg = "extra character after reading grime: "
    msg.addQuoted(reader.data.peekOrZero())
    raise newException(GrimeReadError, msg)

proc fromFlatGrime*[T](s: string, x: typedesc[T]): T {.inline.} =
  fromGrime(s, T, GrimeReadFormat(shared: GrimeFormat(dict: false)))

proc fromDictGrime*[T](s: string, x: typedesc[T]): T {.inline.} =
  fromGrime(s, T, GrimeReadFormat(shared: GrimeFormat(dict: true)))

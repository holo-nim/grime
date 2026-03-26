import ./common, holo_flow/[holo_reader, holo_writer], std/tables

type SizeImpl* = int

template dictByteCount*[T: ref | ptr](format: static GrimeFormat, x: T): int =
  sizeof(DictionaryIdImpl)

template derefPointer*[T: ref | ptr](format: static GrimeDumpFormat, x: T): untyped =
  x[]

proc dumpPointer*[T](
    format: static GrimeDumpFormat,
    dumper: var GrimeDumper,
    val: T) =
  mixin dump, derefPointer, byteCount
  if val.isNil:
    dump(format, dumper, DictionaryIdImpl(0))
  else:
    var p: ReferenceIdentity
    when nimvm:
      p = ReferenceIdentity(dumper.dictIds.len + 1)
    else:
      when defined(nimscript) or defined(js):
        p = ReferenceIdentity(dumper.dictIds.len + 1)
      else:
        p = cast[ReferenceIdentity](cast[pointer](val))
    #echo "got identity ", $p.uint, " for type ", T
    if p in dumper.dictIds:
      let id = dumper.dictIds[p]
      #echo "found at ", id.int
      dump(format, dumper, id)
    else:
      #echo "registering to ", dumper.dictIds.len + 1
      let id = DictionaryId(dumper.dictIds.len + 1)
      dumper.dictIds[p] = id
      # option to calculate this or write it out could go in format:
      let size = byteCount(format.shared, derefPointer(format, val))
      var dictEntry = initHoloWriter()
      dictEntry.startWrite()
      swap dumper.data, dictEntry
      dump(format, dumper, SizeImpl size)
      dump(format, dumper, derefPointer(format, val))
      swap dumper.data, dictEntry
      dumper.dict.write finishWrite(dictEntry)
      dump(format, dumper, id)

type GrimeMergeFormat* = object
  inner*: GrimeDumpFormat

proc merge*(format: static GrimeMergeFormat, writer: var HoloWriter, dump: sink GrimeDumper) =
  writer.write finishWrite(dump.dict)
  var dumper = GrimeDumper()
  swap dumper.data, writer
  dump(format.inner, dumper, SizeImpl -1)
  swap dumper.data, writer
  writer.write finishWrite(dump.data)

type GrimeSplitFormat* = object
  inner*: GrimeReadFormat

when defined(js):
  type SplitReader = var HoloReader
else:
  type SplitReader = sink HoloReader

proc split*(format: static GrimeSplitFormat, reader: SplitReader, merged: var GrimeReader) =
  mixin read
  while true:
    var size: SizeImpl
    var sizeReader = GrimeReader()
    swap sizeReader.data, reader
    read(format.inner, sizeReader, size)
    swap sizeReader.data, reader
    if size < 0:
      break
    var data = newString(size)
    if peek(reader, data):
      unsafeNextBy(reader, size)
      var entry = initHoloReader()
      startRead(entry, move data)
      merged.dict.data.add entry
    else:
      raise newException(GrimeDictError, "expected " & $size & " bytes for dict entry but reached end")
  merged.data = move reader

template allocPointer*[T: ref](format: static GrimeReadFormat, x: var T) =
  new(x)
template allocPointer*[T: ptr](format: static GrimeReadFormat, x: var T) =
  x = create(T)

proc readPointer*[T](
    format: static GrimeReadFormat,
    reader: var GrimeReader,
    val: var T) =
  mixin read, allocPointer
  var idImpl: DictionaryIdImpl
  read(format, reader, idImpl)
  if idImpl == DictionaryIdImpl(0):
    val = nil
  else:
    let id = DictionaryId(idImpl)
    #echo "got ", idImpl, " of type ", T
    if id in reader.dictPointers:
      #echo "existed"
      let p = reader.dictPointers[id]
      when nimvm:
        raiseAssert("cannot read from pointer")
      else:
        val = cast[T](p)
    else:
      #echo "creating"
      let index = (idImpl - 1)
      if index < 0 or index >= reader.dict.data.len:
        raise newException(GrimeDictError, "got dict index: " & $index & " in dict of size: " & $reader.dict.data.len)
      allocPointer(format, val)
      # probably important to do this before reading so cycles know which pointer to use:
      when nimvm:
        discard
      else:
        reader.dictPointers[id] = cast[pointer](val)
      var dictReader = move reader.dict.data[index]
      swap reader.data, dictReader
      read(format, reader, val[])
      swap reader.data, dictReader

when false:
  proc read*[T](
      format: static GrimeReadFormat,
      reader: var GrimeReader,
      val: var ref T) =
    readPointer(format, reader, val)

  proc read*[T](
      format: static GrimeReadFormat,
      reader: var GrimeReader,
      val: var ptr T) =
    readPointer(format, reader, val)

  proc dumpDictGrime*[T](writer: var HoloWriter, v: T, format: static GrimeDictMergeFormat) {.inline.} =
    mixin dump
    dump(GrimeDumpFormat(), writer, v)

  proc dumpFlatGrime*[T](s: var string, v: T) {.inline.} =
    mixin dump
    dump(GrimeDumpFormat(), s, v)

  proc readFlatGrime*[T](reader: var HoloReader, v: var T) {.inline.} =
    mixin read
    read(GrimeReadFormat(), reader, v)

  proc readFlatGrime*[T](reader: var HoloReader, _: typedesc[T]): T {.inline.} =
    mixin read
    read(GrimeReadFormat(), reader, result)

  proc toFlatGrime*[T](v: T): string {.inline.} =
    mixin dump
    dump(GrimeDumpFormat(), result, v)

  proc fromFlatGrime*[T](s: string, x: typedesc[T], format: static GrimeReadFormat = GrimeReadFormat()): T {.inline.} =
    mixin read
    result = default(T)
    var reader = initHoloReader(doLineColumn = false) # XXX byte offset instead of line column
    reader.startRead(s)
    read(format, reader, result)
    if reader.hasNext():
      var msg = "extra character after reading grime: "
      msg.addQuoted(reader.peekOrZero())
      raise newException(GrimeReadError, msg)

import ./common, holo_flow/[holo_reader, holo_writer], std/[tables, macros, macrocache]

type SizeImpl* = int

template dictByteCount*[T: ref | ptr](format: static GrimeFormat, x: T): int =
  sizeof(DictionaryIdImpl)

when defined(js) and grimeTrackJsDictReferences:
  var grimeReferenceMap: int
  var grimeReferenceCount = 0
  {.emit: """
  `grimeReferenceMap` = new WeakMap();
  """.}

proc getReferenceIdentity*[T: ref | ptr](format: static GrimeDumpFormat, dumper: var GrimeDumper, x: T): ReferenceIdentity {.inline.} =
  when nimvm:
    when false: # does not work
      var tracked {.global.}: seq[(T, int)] = @[]
      const countedReferences = CacheCounter"grime.referenceidentities"
      for p, i in tracked.items:
        if x == p: return ReferenceIdentity(i)
      inc countedReferences
      result = ReferenceIdentity(countedReferences.value)
      tracked.add (x, result.int)
    else:
      result = ReferenceIdentity(dumper.dictIds.len + 1)
  else:
    when defined(nimscript):
      result = ReferenceIdentity(dumper.dictIds.len + 1)
    elif defined(js):
      when grimeTrackJsDictReferences:
        {.emit: ["""
        if (""", grimeReferenceMap, """.has(""", x, """)) {
          """, result, """ = """, grimeReferenceMap, """.get(""", x, """);
        } else {
          """, result, """ = ++""", grimeReferenceCount, """;
          """, grimeReferenceMap, """.set(""", x, """, """, result, """);
        }
        """].}
      else:
        result = ReferenceIdentity(dumper.dictIds.len + 1)
    else:
      result = cast[ReferenceIdentity](cast[pointer](x))

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
    let p = getReferenceIdentity(format, dumper, val)
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
      var trailingDict = initHoloWriter()
      trailingDict.startWrite()
      swap dumper.dict, dumper.data
      swap trailingDict, dumper.dict
      dump(format, dumper, SizeImpl size)
      dump(format, dumper, derefPointer(format, val))
      swap trailingDict, dumper.dict
      swap dumper.dict, dumper.data
      dumper.dict.write finishWrite(trailingDict)
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
      #echo "read entry ", merged.dict.data.len, " with size ", size, ": ", data.toOpenArrayByte(0, data.high)
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
        reader.dictPointers[id] = cast[AnyPointer](val)
      var dictReader = move reader.dict.data[index]
      swap reader.data, dictReader
      read(format, reader, val[])
      swap reader.data, dictReader

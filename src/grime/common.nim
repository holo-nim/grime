import holo_flow/[load_reader, flush_writer], std/[tables, hashes]

type
  GrimeFormat* = object
    endian*: Endianness = cpuEndian
    dict*: bool
  GrimeDumpFormat* = object
    shared*: GrimeFormat
  GrimeReadFormat* = object
    shared*: GrimeFormat
    skip*: bool
      ## skip current value

const grimeTrackJsDictReferences* {.booldefine.} = true
  ## uses a global map to get the reference identities of reference objects in JS to use in dicts

type
  AnyPointer* = (
    when defined(js):
      JsRoot
    else:
      pointer
  )
  DictionaryIdImpl* = int
  DictionaryId* = distinct DictionaryIdImpl
  ReferenceIdentity* = distinct uint
  Dictionary* = object
    data*: seq[LoadReader] # DictionaryId are indexes + 1, since 0 is nil
  GrimeDumper* = object
    dict*: FlushWriter
    dictIds*: OrderedTable[ReferenceIdentity, DictionaryId]
    data*: FlushWriter
  GrimeReader* = object
    dict*: Dictionary
    dictPointers*: OrderedTable[DictionaryId, AnyPointer]
    data*: LoadReader

proc `==`*(a, b: DictionaryId): bool {.borrow.}
proc hash*(a: DictionaryId): Hash {.borrow.}
proc `==`*(a, b: ReferenceIdentity): bool {.borrow.}
proc hash*(a: ReferenceIdentity): Hash {.borrow.}

type
  SomeGrimeFormat* = GrimeReadFormat | GrimeDumpFormat

type
  GrimeError* = object of ValueError
  GrimeValueError* = object of GrimeError
    ## error for when a value can be read,
    ## but could not be fit into the expected value
  GrimeReadError* = object of GrimeError
    ## error for invalid binary
  GrimeDictError* = object of GrimeError
    ## error for a value that could not be found in the dictionary

when (compiles do: import cosm/groups):
  import cosm/groups
  const Grime* = MappingGroup(id: "grime", parents: @[Binary])

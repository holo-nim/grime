type
  GrimeReadFormat* = object
    endian*: Endianness = cpuEndian
    skip*: bool
      ## skip current value
  GrimeDumpFormat* = object
    endian*: Endianness = cpuEndian

type
  GrimeError* = object of ValueError
  GrimeValueError* = object of GrimeError
    ## error for when a value can be read,
    ## but could not be fit into the expected value
  GrimeReadError* = object of GrimeError
    ## error for invalid binary

when (compiles do: import holo_map/groups):
  import holo_map/groups
  const Grime* = MappingGroup(id: "grime", parents: @[])

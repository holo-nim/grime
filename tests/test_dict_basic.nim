import grime

type
  Foo {.inheritable.} = object
    a: string
    case b: uint8
    of 0..2:
      c: int
      d: bool
    else:
      e: float

  Bar = ref object of Foo
    f: int

  Obj = object
    field1: string
    field2: Foo
    field3: Bar
    field4: seq[Obj]

  RefObj = object
    field1: string
    field2: Foo
    field3: Bar
    field4: seq[RefObj]

proc `$`(b: Bar): string =
  if b.isNil: "nil" else: $b[]

proc `==`(a, b: Foo): bool {.noSideEffect.} =
  if a.a != b.a: return false
  if a.b != b.b: return false
  case a.b
  of 0..2:
    if a.c != b.c: return false
    if a.d != b.d: return false
  else:
    if a.e != b.e: return false
  result = true

proc `==`(a, b: typeof(Bar()[])): bool {.noSideEffect.} =
  if a.a != b.a: return false
  if a.b != b.b: return false
  case a.b
  of 0..2:
    if a.c != b.c: return false
    if a.d != b.d: return false
  else:
    if a.e != b.e: return false
  if a.f != b.f: return false
  result = true

proc `==`(a, b: Bar): bool {.noSideEffect.} =
  system.`==`(a, b) or (not a.isNil and not b.isNil and a[] == b[])

proc `==`(a, b: Obj): bool {.noSideEffect.} =
  if a.field1 != b.field1: return false
  if a.field2 != b.field2: return false
  if a.field3 != b.field3: return false
  if a.field4 != b.field4: return false
  result = true

proc `==`(a, b: RefObj): bool {.noSideEffect.} =
  if a.field1 != b.field1: return false
  if a.field2 != b.field2: return false
  if a.field3 != b.field3: return false
  if a.field4 != b.field4: return false
  result = true

proc test() =
  var obj = Obj(
    field1: "field 1",
    field2: Foo(a: "abc", b: 1, c: 123, d: false),
    field3: Bar(a: "def", b: 2, c: 456, d: true, f: 1000),
    field4: @[
      Obj(
        field1: "nested 1",
        field2: Foo(a: "ghi", b: 3, e: 1.23),
        field3: Bar(a: "jkl", b: 4, e: 4.56, f: 2000),
        field4: @[]
      ),
      Obj(
        field1: "nested 2",
        field2: Foo(a: "mno", b: 100, e: 7.89),
        field3: nil,
        field4: @[
          Obj(
            field1: "nested 3",
            field2: Foo(a: "pqr", b: 255, e: NegInf),
            field3: Bar(a: "stu", b: 0, c: 789, d: true, f: 3000)
          )
        ]
      )
    ]
  )
  obj.field4.add obj

  when false: echo "serializing:"
  let ser = toDictGrime(obj)
  when false:
    import std/strutils
    for c in ser:
      if c in {'\0'..'\32', '\127'..'\255'}:
        stdout.write toHex(byte(c))
      else:
        stdout.write c
      stdout.write ' '
    stdout.writeLine("")
  when false: echo "deserializing:"
  let des = fromDictGrime(ser, Obj)
  doAssert obj == des, $des
  when false: echo $des

static: test()
test()

proc nestedTest() =
  var obj = RefObj(
    field1: "field 1",
    field2: Foo(a: "abc", b: 1, c: 123, d: false),
    field3: Bar(a: "def", b: 2, c: 456, d: true, f: 1000),
    field4: @[
      RefObj(
        field1: "nested 1",
        field2: Foo(a: "ghi", b: 3, e: 1.23),
        field3: Bar(a: "jkl", b: 4, e: 4.56, f: 2000),
        field4: @[]
      ),
      RefObj(
        field1: "nested 2",
        field2: Foo(a: "mno", b: 100, e: 7.89),
        field3: nil,
        field4: @[
          RefObj(
            field1: "nested 3",
            field2: Foo(a: "pqr", b: 255, e: NegInf),
            field3: Bar(a: "stu", b: 0, c: 789, d: true, f: 3000)
          )
        ]
      )
    ]
  )
  obj.field4[0].field4.add obj
  obj.field4[1].field4[0].field4.add obj.field4[0]
  obj.field4[1].field4[0].field4.add obj
  obj.field4.add obj

  when false: echo "serializing:"
  let ser = toDictGrime(obj)
  when false:
    import std/strutils
    for c in ser:
      if c in {'\0'..'\32', '\127'..'\255'}:
        stdout.write toHex(byte(c))
      else:
        stdout.write c
      stdout.write ' '
    stdout.writeLine("")
  when false: echo "deserializing:"
  let des = fromDictGrime(ser, RefObj)
  doAssert obj == des, $des
  when false: echo $des

static: nestedTest()
nestedTest()

proc cycleTest() =
  type
    Cycle1 = ref object
      bar: Cycle2
    Cycle2 = ref object
      foo: Cycle1
  var x = Cycle1()
  x.bar = Cycle2()
  x.bar.foo = x

  let ser2 = toDictGrime(x)
  let des2 = fromDictGrime(ser2, Cycle1)
  doAssert des2.bar.foo == des2

  type
    TripleCycle1 = ref object
      a: TripleCycle2
    TripleCycle2 = ref object
      b: TripleCycle3
    TripleCycle3 = ref object
      c: TripleCycle1
  var x3 = TripleCycle1()
  x3.a = TripleCycle2()
  x3.a.b = TripleCycle3()
  x3.a.b.c = x3

  let ser3 = toDictGrime(x3)
  let des3 = fromDictGrime(ser3, TripleCycle1)
  doAssert des3.a.b.c == des3

static:
  if false:
    cycleTest()
if not (defined(nimscript) or (defined(js) and not grimeTrackJsDictReferences)):
  cycleTest()


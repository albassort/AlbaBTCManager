import db_connector/db_sqlite
import std/parseutils
import sequtils
import strutils
import times
import std/options
import std/uri
import tables
import Json

proc assignFromString[T](a : string, b : var T) {.gcsafe.}  =
  let boolConverstionTable = {"f" : false, "t" : true}.toTable()

  when b is string:
    if a.len != 0:
      b = a
  when b is int or b is int64 or b is int32 or b is int16 or b is int8:
    if a!= "":
      b = parseInt(a)
    else:
      b = 0
  when b is uint or b is uint8 or b is uint16 or b is uint32 or b is uint64:
    if a != "":
      b = parseUInt(a)
    else:
      b = 0
    b = parsePostgresTime(a)
  when b is Time:
    b = fromUnix(parseInt(a))
  when b is bool:
    if a in boolConverstionTable:
      b = boolConverstionTable[a]
    else:
      b = parseBool(a)
  when b is float:
    b = parseFloat(a)
  when b is Option:
    if a.high == -1:
      b = none[b.T]()
    else:
      let newVariable = new b.T
      var dereference = newVariable[]
      assignFromString(a, dereference)
      b = some(dereference)
  when b is JsonNode:
    b = parseJson(a)

proc convertRow[T](row: Row) : Option[T] {.gcsafe.}  =
  # Internal, attempts to convert a row to the given type
  try:
    var generic = new result.T
    var i = 0
    for x,y in fieldPairs(generic[]):
      assignFromString(row[i], y)
      i+=1
    doAssert(i == row.len)
    return some(generic[])
  except:
    echo row
  
    echo getCurrentException()[]
    return none(T)

iterator fastRowsTyped*[T](db: DbConn,
                        query: SqlQuery,
                        args: varargs[string, `$`]) : Option[T] =

  ## Iterates over the given query, returning all rows converted to the output type

  for row in db.fastRows(query, args):
    yield convertRow[T](row)

iterator fastRowsTyped*[T](db: DbConn,
                        query: SqlPrepared) : Option[T]  {.gcsafe.} =
  ## Iterates over the given query, returning all rows converted to the output type

  for row in db.fastRows(query):
    yield convertRow[T](row)

proc getRowTyped*[T](db: DbConn,
                        query: SqlQuery,
                        args: varargs[string, `$`]) : Option[T] {.gcsafe.}  =

  ## converts a single row from the query.
  return convertRow[T] db.getRow(query, args)



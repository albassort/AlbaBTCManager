import db_connector/db_sqlite
import json
import std/parseutils
import sequtils
import strutils
import times
import std/options
import std/uri
import tables
import Json
import typetraits
import ./shared

##TODO MAKE A BETTER ORM
type CanConvert = concept x 
  $x is string


proc assignFromString[T](a : string, b : var T) {.gcsafe.}  =

  when b is string:
    if a.len != 0:
      b = a
  elif b is SomeSignedInt:
    if a!= "":
      b = parseInt(a)
    else:
      b = 0
  elif b is SomeUnsignedInt:
    if a != "":
      b = parseUInt(a)
    else:
      b = 0
  elif b is Time:
    #TODO: enforce UTC time.
    b = fromUnix(parseInt(a))
  elif b is bool:
    b = 
      case a
      of "f":
        false
      of "t":
        true
      else:
        parseBool(a)
  elif b is float:
    b = parseFloat(a)
  elif b is Option:
    if a.high == -1:
      b = none[b.T]()
    else:
      let newVariable = new b.T
      var dereference = newVariable[]
      assignFromString(a, dereference)
      b = some(dereference)
  elif b is JsonNode:
    b = parseJson(a)
  elif b is CoinType:
    b = parseEnum[CoinType](a)

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



import db_connector/db_sqlite
import std/parseutils
import sequtils
import strutils
import times
import std/options
import std/uri
import tables

#type  canSerialize* = concept x
#    isSome x
#    isNone x
proc assignFromString[T](a : string, b : var T) =
  when b is string:
    if a.len != 0:
      b = a
  when b is int or b is int64 or b is int32 or b is int16 or b is int8:
    if a!= "":
      b = parseInt(a)
    else:
      b = 0
  when b is uint8 or b is uint16 or b is uint32 or b is uint64:
    if a != "":
      b = parseUInt(a)
    else:
      b = 0
  when b is Time:
    b = fromUnix(parseInt(a))
  when b is bool:
    b = parseBool(a)
  when b is float:
    b = parseFloat(a)
  #echo ("after->", row[i], x, y)

proc convertRow*[T](row: Row) : Option[T] =
  try:
    var generic = new result.T
    var i = 0
    for x,y in fieldPairs(generic[]):
      echo ("before->", row[i], x, y)
      assignFromString(row[i], y)
      i+=1
    doAssert(i == row.len)
    return some(generic[])
  except Exception as e:
    echo e[] 
    return none(T)

iterator fastRowsTyped*[T](db: DbConn,
                        query: SqlQuery,
                        args: varargs[string, `$`]) : Option[T] =

  for row in db.fastRows(query, args):
    yield convertRow[T](row)

iterator fastRowsTyped*[T](db: DbConn,
                        query: SqlPrepared) : Option[T] =

  for row in db.fastRows(query):
    yield convertRow[T](row)

proc getRowTyped*[T](db: DbConn,
                        query: SqlQuery,
                        args: varargs[string, `$`]) : Option[T] =

  return convertRow[T] db.getRow(query, args)

proc convertUriQueryToTable*(a : Uri) : Table[string, string] =
  let decode = decodeQuery(a.query).toSeq()
  for keyval in decode:
    let key = keyval[0]
    let val = keyval[1]
    if not key.isEmptyOrWhitespace():
      echo (key,val)
      result[key.toUpper()] = val
  echo result


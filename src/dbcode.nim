import times 
import db_connector/db_sqlite
import std/options
import Json
import NimBTC
import tables
import ./cheapORMSqlite
import sequtils
import sugar
import groupBy
import strutils
import shared

proc `$`(a : float64 | float | float32) : string =
  formatBiggestFloat(a, ffDecimal)

converter toString(a : float64 | float | float32) : string =
  formatBiggestFloat(a, ffDecimal)

type 
  WithdrawalStrategy* = enum
    Group = "group", Single = "single"
  CryptoTypes* = enum
    BTC = "BTC"
  User* = object
    rowId* : int
    userName* : string
    password* : string
    saltIv* : string
    accountCreationTime* : Time
    IsActive* : bool
  RpcLog* = object
    rowId* : int
    userRowId* : Option[int]
    validLogin* : bool
    timeRecieved* : Time
    RequestBody* : JsonNode
  UserCryptoChange* = object
    rowId* : int
    time* : Time
    userRowId* : int
    cryptoType : string
    crytpoChange : float64
    withdrawalRowId* : Option[int]
    depositRowId* : Option[int]
    miscCause* : Option[string]
  DepositRequest* = object
    rowId* : int
    address* : string
    coinType* : CryptoTypes
    validLengthSeconds* : int
    payToUser* : Option[int]
    depositAmount* : float64
    finished* : bool
    expired* : bool
    isActive* : bool
    timeStarted* : Time
    timeEnded* : Option[Time]

  DepositEvent* = object
    rowId* : int
    DepositRequest* : int
    AmounntRecieved* : float64
    timeRecieved* : float64
  TransactionData* = object
    rowId* : int
    time* : Time
    fee* : float64
    OutputTotal* : float64
    numberOfOutputs* : uint
    transactionBody* : JsonNode
    txid* : string
  WithdrawalRequest* = object
    rowId* : int
    userRowId* : int64
    timeRecieved* : Time 
    cryptoType* : CryptoTypes
    cryptoAmount* : float64
    withdrawalStrategy* : WithdrawalStrategy
    withdrawalAddress* : string
    timeComplete* : Option[Time]
    isComplete* : bool
    isActive* : bool

proc insertWithdrawalRequest*(db : DbConn, userRowId : int, cryptoType : CryptoTypes, strategy : WithdrawalStrategy,  amount : float64, address : string) : int64 =
  return db.insertId(sql"insert into WithdrawalRequest(UserRowId, CryptoType, CryptoAmount,  WithdrawalStrategy, WithdrawalAddress) VALUES (?,?,?,?,?)", userRowId, $cryptoType, amount, $strategy, address)

proc dbCommitBalanceChange*(db : DbConn, userRowId : int, cryptoType : CryptoTypes, amount : float64, 
  depositRequestRowId = -1, withdarawalRequestRowId = -1) =

  doAssert depositRequestRowId == -1 xor withdarawalRequestRowId == -1

  db.exec(sql"insert into UserCryptoChange(UserRowId, CryptoType, CryptoChange, DepositRowId, WithdrawalRowId) values (?, ?, ?, NULLIF(?, -1), NULLIF(?, -1))",
    userRowId, $cryptoType, amount, depositRequestRowId, withdarawalRequestRowId)
  
proc createNewDepositRequest*(db : DbConn, address : string, cryptoType : CryptoTypes, withdrawalExpireTime : int, depositAmount : float, userRowId = 1) : int = 

  let insert = sql"""insert into DepositRequest(ReceivingAddress, CoinType, ValidLengthSeconds, PayToUser, DepositAmount) values (?, ?, ?, ?, ?)"""
  return db.insertId(insert, address, $cryptoType, withdrawalExpireTime, userRowId, $depositAmount)
  discard ""
  #discard getNewAddress
 
proc getAmountForUserByCrypto*(db : DbConn, userRowId : int) : Table[CryptoTypes, float64] =  

  const totalCryptoForType = sql"select sum(CryptoChange), CryptoType from UserCryptoChange where UserRowId = ? group by CryptoType"

  result = fastRowsTyped[(float64, string)](db, totalCryptoForType, userRowId).toSeq().map(x=>x.get()).keyVal(x=> parseEnum[CryptoTypes](x[1]), x=> x[0])
  for kind in CryptoTypes:
    if kind notin result:
      result[kind] = 0.0

proc createWithdrawalRequest*(db : DbConn, address : string, amount : float64, cryptoType : CryptoTypes, userRowId : int, withdrawalStrategy: WithdrawalStrategy) : int = 

  let insert = sql"""insert into WithdrawalRequest(userRowId, cryptoType, cryptoAmount, withdrawalStrategy, withdrawalAddress
  ) values (?, ?, ?, ?, ?)"""
  return db.insertId(insert, cryptoType, amount, $cryptoType, address)

proc getUserByRowid*(db : DbConn, userRowId : int) : Option[User] = 
  getRowTyped[User](db, sql"select rowid, * from Users where RowId = ?", userRowId)


#   db.exec(sql"insert into WithdrawalRequest(CoinType, CryptoAmount,  WithdrawalStrategy, WithdrawalAddress, PayToUser) VALUES (?,?,?,?,?)", userRowId, $cryptoType, cryptoAmount, $strategy, address)

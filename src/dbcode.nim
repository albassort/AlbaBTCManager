import times 
import db_connector/db_sqlite
import std/options
import json
import NimBTC
import tables
import ./cheapORMSqlite
import sequtils
import sugar
import groupBy
import strutils
import ./shared
type 

  WithdrawalStrategy* = enum
    Group = "group", Single = "single"
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
    timeReceived* : Time
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
    coinType* : CoinType
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
    AmounntReceived* : float64
    timeReceived* : float64
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
    timeReceived* : Time 
    cryptoType* : CoinType
    cryptoAmount* : float64
    withdrawalStrategy* : WithdrawalStrategy
    withdrawalAddress* : string
    timeComplete* : Option[Time]
    isComplete* : bool
  TransactionWatch* = object
    rowId : int
    txId* : string
    blockHeightCreated* : string 
    confTarget* : int
    callBack* : JsonNode
    cryptoType* : CoinType
    notified* : bool
    motFound* : bool

proc insertWithdrawalRequest*(db : DbConn, userRowId : int, cryptoType : CoinType, strategy : WithdrawalStrategy,  amount : float64, address : string) : int64 =
  return db.insertId(sql"insert into WithdrawalRequest(UserRowId, CoinType, CryptoAmount,  WithdrawalStrategy, WithdrawalAddress) VALUES (?,?,?,?,?)", userRowId, $cryptoType, amount, $strategy, address)

proc dbCommitBalanceChange*(db : DbConn, userRowId : int, cryptoType : CoinType, amount : float64, 
  depositRequestRowId = -1, withdarawalRequestRowId = -1) =

  doAssert depositRequestRowId == -1 xor withdarawalRequestRowId == -1

  db.exec(sql"insert into UserCryptoChange(UserRowId, CoinType, CryptoChange, DepositRowId, WithdrawalRowId) values (?, ?, ?, NULLIF(?, -1), NULLIF(?, -1))",
    userRowId, $cryptoType, amount, depositRequestRowId, withdarawalRequestRowId)
  
proc createNewDepositRequest*(db : DbConn, address : string, cryptoType : CoinType, withdrawalExpireTime : uint64, depositAmount : float, userRowId = 1, callback = newJNull()) : int = 

  let insert = sql"""insert into DepositRequest(ReceivingAddress, CoinType, ValidLengthSeconds, PayToUser, DepositAmount, Callback) values (?, ?, ?, ?, ?, NULLIF(?, "null"))"""
  return db.insertId(insert, address, $cryptoType, withdrawalExpireTime, userRowId, depositAmount)
  discard ""
  #discard getNewAddress
 
proc getAmountForUserByCrypto(db : DbConn, userRowId : int) : Table[CoinType, float64] =  

  const totalCryptoForType = sql"select sum(CryptoChange), CoinType from UserCryptoChange where UserRowId = ? group by CoinType"

  result = fastRowsTyped[(float64, string)](db, totalCryptoForType, userRowId).toSeq().map(x=>x.get()).keyVal(x=> parseEnum[CoinType](x[1]), x=> x[0])
  for kind in CoinType:
    if kind notin result:
      result[kind] = 0

proc createWithdrawalRequest*(db : DbConn, address : string, amount : float64, cryptoType : CoinType, userRowId : int, withdrawalStrategy: WithdrawalStrategy) : int = 

  let insert = sql"""insert into WithdrawalRequest(userRowId, cryptoType, cryptoAmount, withdrawalStrategy, withdrawalAddress
  ) values (?, ?, ?, ?, ?)"""
  return db.insertId(insert, cryptoType, amount, $cryptoType, address)

proc insertTxWatch*(db : DbConn, txId : string, blockHeightCreated, confTarget : int,  cryptoType : CoinType, callBack = newJNull()) : int = 
  let insert = sql"""insert into TransactionWatch(Txid, BlockHeightCreated, ConfTarget, CallBack, CoinType)
  values (?, ?,?, NULLIF(?, 'null'),?)"""
  return db.insertId(insert, txId, blockHeightCreated, confTarget, $callBack,  cryptoType)
  
proc userExists*(db : DbConn, userRowId : int) : bool = 
  let row = db.getRow(sql"select * from Users where rowId = ?", userRowId)

  if row[0] != "": return true
   
proc getUser*(db : DbConn, userRowId : uint64) : Option[User] = 

  getRowTyped[User](db, sql"select rowid, * from users where userRowid =?", userRowId)

#   db.exec(sql"insert into WithdrawalRequest(CoinType, CryptoAmount,  WithdrawalStrategy, WithdrawalAddress, PayToUser) VALUES (?,?,?,?,?)", userRowId, $cryptoType, cryptoAmount, $strategy, address)

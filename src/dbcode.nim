import times 
import db_connector/db_sqlite
import std/options
import Json
type 

  WithdrawalStrategy* = enum
    Group, Single
  CryptoTypes* = enum
    BTC = "BTC"
  User* = object
    rowId* : int
    userName* : string
    password* : string
    saltIv* : string
    accountCreationTime* : DateTime
    IsActive* : bool
  RpcLog* = object
    rowId* : int
    userRowId* : Option[int]
    validLogin* : bool
    timeRecieved* : DateTime
    RequestBody* : JsonNode
  UserCryptoChange* = object
    rowId* : int
    time* : DateTime
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
    timeStarted* : Datetime
    timeEnded* : DateTime

  DepositEvent* = object
    rowId* : int
    DepositRequest* : int
    AmounntRecieved* : float64
    timeRecieved* : float64
  TransactionData* = object
    rowId* : int
    time* : DateTime
    fee* : float64
    OutputTotal* : float64
    numberOfOutputs* : uint
    transactionBody* : JsonNode
    txid* : string
  WithdrawalRequest* = object
    rowId* : int
    userRowId* : int64
    timeRecieved* : DateTime 
    cryptoType* : CryptoTypes
    cryptoAmount* : float64
    withdrawalStrategy* : WithdrawalStrategy
    withdrawalAddress* : string
    timeComplete* : Option[DateTime]
    isComplete* : bool

proc insertWithdrawalRequest*(db : DbConn, userRowId : int, cryptoType : CryptoTypes, strategy : WithdrawalStrategy,  amount : float64, address : string) : int64 =
  return db.insertId(sql"insert into WithdrawalRequest(UserRowId, CryptoType, CryptoAmount,  WithdrawalStrategy, WithdrawalAddress) VALUES (?,?,?,?,?)", userRowId, $cryptoType, amount, $strategy, address)

proc dbCommitBalanceChange*(db : DbConn, userRowId : int, cryptoType : CryptoTypes, amount : float64, 
  depositRequestRowId = -1, withdarawalRequestRowId = -1) =

  doAssert depositRequestRowId == -1 xor withdarawalRequestRowId == -1

  db.exec(sql"insert into UserCryptoChange(UserRowId, CryptoType, CryptoChange, DepositRowId, WithdrawalRowId) values (?, ?, ?, NULLIF(?, -1), NULLIF(?, -1)",
    userRowId, $cryptoType, amount, depositRequestRowId, withdarawalRequestRowId)
  
# proc insertNewDepositRequest*(db : DbConn, cryptoAmount : float64, cryptoType : CryptoTypes, userRowId = 1) =
#   db.exec(sql"insert into WithdrawalRequest(CoinType, CryptoAmount,  WithdrawalStrategy, WithdrawalAddress, PayToUser) VALUES (?,?,?,?,?)", userRowId, $cryptoType, cryptoAmount, $strategy, address)

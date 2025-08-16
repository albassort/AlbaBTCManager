import ./dbcode
import json
import tables
import results
import NimBTC
import std/options
import db_connector/db_sqlite
import sets
import ./cheapORMSqlite
import sequtils
import sugar
import times
import ./btccode
import groupBy
import ./dbcode
export dbcode

type
  CryptoClients* = object
    btcClient* : Option[BTCClient]
  DepositOutcome* = enum
    NoChange = "noChange", FundingIncreased = "fundingIncreased", Expired = "expired", FullyFunded = "fullyFunded"
  Exceptions*  = enum
    ErrorChangingRow = "errorUpdatingRow", NotEnoughFunds = "notEnoughFunds", FailedToCreateTx = "failedToCreateTx",
    FailedToSubmitRawTx = "failedToSubmitRawTx", MultipleCoinsInWithdrawal = "multipleCoinsInWithdrawal", IncorrectCoinInWithdrawal = "incorrectCoinInWithdrawal", addresNotFound = "addresNotFound"

proc judgeDeposit(db : DbCOnn, isFinished, isExpired : bool, rowid : int) =  
  db.exec(sql"update DepositRequest set Finished = ?, Expired = ?, TimeEnded = (strftime('%s','now')) where rowid = ?", isFinished, isExpired, rowid)

proc endWithdrawal(db : DbConn, rowid : int) = 
  db.exec(sql"update WithdrawalRequest set isComplete = true, TimeEnded = (strftime('%s','now')) where rowid = ?", rowid)

proc validateDepositsBTC*(client : BTCClient, db : DbConn,  a : DepositRequest, change : var float64, total : var float64): Result[DepositOutcome, Exceptions] {.gcsafe.} =

  let currentTime = now().utc.toTime

  
  let validLength = fromUnix(a.timeStarted.toUnix+a.validLengthSeconds)
  if currentTime > validLength:
    judgeDeposit(db, true, true, a.rowid)
    return ok Expired

  let totalSendSoFar = getRowTyped[(float64,)](db, sql"select coalesce(sum(AmountReceived), 0) from DepositEvent where DepositRequest = ?", a.rowId).get()[0]

  let addressFound = getreceivedbyaddress(client, a.address)

  if addressFound.isErr:
    return err addresNotFound

  let amountDeposited = addressFound.resultObject.getFloat()
  echo addressFound

  if amountDeposited > totalSendSoFar:
    let change = amountDeposited-totalSendSoFar
    db.exec(sql"insert into DepositEvent(DepositRequest, AmountReceived) values(?,?)", a.rowId, change)

  if a.depositAmount > amountDeposited:
    return ok FundingIncreased

  judgeDeposit(db, true, false, a.rowid)

  return ok FullyFunded

const totalCryptoForType = sql"select coalesce(sum(CryptoChange), 0) from UserCryptoChange where CryptoType = ? and userRowId = ?"

#PRAGMA busy_timeout = 5000;
#
proc createWithdrawalRequest*(db : DbConn, user : User, address : string, coinType : CryptoTypes, withdrawalType: WithdrawalStrategy, coinAmount : float64) : Result[void, Exceptions] =
  let totalCurrency = getRowTyped[(float64,)](db, totalCryptoForType, $coinType, user.rowId).get()[0]
  if totalCurrency > coinAmount:
    return err NotEnoughFunds
  let id = insertWithdrawalRequest(db, user.rowId, coinType, withdrawalType, coinAmount, address)
  dbCommitBalanceChange(db, user.rowid, coinType, coinAmount, id)


proc handleWidhtrawals*(clients : CryptoClients, coinType: CryptoTypes, db : DbConn, a : seq[WithdrawalRequest]) : Result[string, Exceptions] =

  if a.map(x=> x.cryptoType).deduplicate().len == 1:
    return err MultipleCoinsInWithdrawal

  if a[0].cryptoType == coinType:
    return err IncorrectCoinInWithdrawal

  let targets = a.groupBy(x => x.withdrawalAddress, x => x.cryptoAmount)
  var outputs = initTable[string, float64]()
  var totalCrypto = 0.0
  for x,y in targets.pairs:
    outputs[x] = y.foldl(a+b)
    totalCrypto += outputs[x]
#  let totalCurrency = getRowTyped[(float64,)](db, totalCryptoForType, a.cryptoType, user.rowId).get()[0]
#  if totalCurrency > a.cryptoAmount:
#    return err NotEnoughFunds

  case coinType:
    of BTC:
      var feeResult = 0.0
      let rawtxunsigned = createTransaction(clients.btcClient.get(), outputs, 6)
      if rawtxunsigned.isErr:
        return err FailedToCreateTx

      let feeEstimate = rawtxunsigned.get().resultObject["fee"].getFloat
      let rawtxunsignedHex = rawtxunsigned.get().resultObject["hex"].getStr

      var signedObject = newJOBject()
      #TODO: wallet password conf system
      # TODO FIX
      # let rawTx = submitRawTransaction(clients.btcClient.get(), rawtxunsignedHex, signedObject)
      #
      # if rawTx.isErr:
      #   return err FailedToSubmitRawTx
      #
      # let hex = rawTx.get().resultObject["hex"].getStr
      #
      # discard db.insertId(sql"insert into TransactionData(FeeEstimate, OutputTotal, NumberOfOputs, TransactionRawHex, TransactionSignedData, TxId)", feeEstimate, totalCrypto, outputs.keys.toSeq().len, hex, $signedObject, signedObject["txid"].getStr)
      #
      # for row in a:
      #   endWithdrawal(db, row.rowId)
      #
proc judgeAllDeposits*(clients : CryptoClients, db : DbConn) : HashSet[int] {.gcsafe.} =
  let rows = fastRowsTyped[DepositRequest](db, sql"""
    select rowid, * from DepositRequest where finished = false and IsActive = true
  """).toSeq().map(x=>x.get())

  echo rows

  if rows.len == 0:
    return

  let t1 = now().utc()
  # var results : seq[(int, Exceptions)]
  var totalPending : uint64 = 0
  var totalExpired : uint64 = 0
  var totalRequests = rows.len
  var failedCount = 0
  var succeededCount = 0
  var errors : Table[string, seq[int]]
  for row in rows:
    case row.coinType
    of BTC:
      let client = clients.btcClient.get()
      var btcChange : float64
      var totalDeposited : float64
      let judge = validateDepositsBTC(client, db, row, btcChange, totalDeposited)

proc judgeAllWithdrawals*(clients : CryptoClients, db : DbConn) : HashSet[int] {.gcsafe.} =
  let rows = fastRowsTyped[WithdrawalRequest](db, sql"""
    select * from WithdrawalRequest where finished = false and IsActive = true
  """).toSeq().map(x=>x.get())

  let byCrypto = rows.groupBy(x=> x.cryptoType, x=> x)
  var usersSkip : HashSet[int]
  for cryptoType, rows in byCrypto.pairs:
    let byAmount = rows.groupBy(x=> x.userRowId, x=>x.cryptoAmount)
    for user, amount in byAmount:
      let total = amount.foldl(a+b)
      let totalCurrency = getRowTyped[(float64,)](db, totalCryptoForType, $cryptoType, user).get()[0]
      if totalCurrency > total:
        usersSkip.incl(user)

    let validWithdarawals = rows.groupBy(x=> x.userRowId notin usersSkip, x=> x)
    discard handleWidhtrawals(clients, cryptoType, db, rows)


proc monitorTxId*(clients : CryptoClients, db : DbConn, txid : string, confTarget : int, callback: JsonNode)  {.gcsafe.} =
  echo callback


proc newDepositRequest*(db : DbConn, clients : CryptoClients, cryptoType: CryptoTypes, depositAmount : float, userRowId : int = 1) : Option[string] {.gcsafe.} =
  case cryptoType:
    of BTC:
      #TODO: check if some; send out notif if not and enabled
      let client = clients.btcClient.get()
      let newAddress = getNewAddress(client, "", BECH32)
      if not newAddress.hasResult:
        echo newAddress 
        return 
      let address = newAddress.resultObject.getStr()

      discard createNewDepositRequest(db, address, BTC, 7200, depositAmount, userRowId)
      return some address



import puppy
import strformat
import strutils
import NimBTC
import Json
import pretty
import sequtils
import sugar
import tables
import results
import std/options
import os
import std/base64
import times
import streams
import locks
import jsony

type HalfBtcResponse* = object
  error* : RpcErrorCode
  errorMessage* : string
type E = Result[BTCResponse, BTCResponse]
#when isMainModule:
 # let tb1 = "tb1qds07ugl6ssw8zsefgdg9hxmwfqcn5c735"
  #print listreceivedbyaddress(client)
type 
  TX* = object
    amount* : float64
    txId* : string
    wTxId* : string
    blockHeight* : options.Option[uint64]
    blockTime* : options.Option[Time]
    confirmations* : uint64
    isAccepted* : bool
    size* : uint64
    vsize* : uint64
    weight* : uint64
    lockTime* : uint64
    fee* : float64

proc queryTx*(client : BTCClient, tx : string) : Option[TX] =

  let txidAttemptGet = getTransaction(client, tx)

  if txidAttemptGet.isErr: return

  let a = getTransaction(client, tx).resultObject
  let newy = new TX
  var result =  newy[]
  
  result.txid = tx
  result.wTxId = a["wtxid"].getStr()
  result.amount = a["amount"].getFloat()
  result.confirmations = uint64 a["confirmations"].getInt()
  result.fee = abs a["fee"].getFloat()
  result.isAccepted = result.confirmations != 0

  if "blockheight" in a:
    result.blockHeight =  some uint64 a["blockheight"].getInt()
  if "blocktime" in a:
    
    result.blocktime =  some fromUnix a["blocktime"].getInt()

  let rawhex = a["hex"].getStr()
  let rawTx = decodeRawTransaction(client, rawHex).resultObject
  
  result.size = uint64 rawTx["size"].getInt()
  result.vsize = uint64 rawTx["vsize"].getInt()
  result.weight = uint64 rawTx["weight"].getInt()
  result.locktime = uint64 rawTx["locktime"].getInt()
  return some result

{.define: regTest.}
proc createTransaction*(client : BTCClient, outputs : Table[string, float], confTarget : uint) : Result[BTCResponse, BTCResponse] =
  ##  MUST BE SIGNED AFTER EXECUTION!!
  var feeTaker : seq[int]
  var i = 0
  for x in outputs.keys:
    feeTaker.add(i)
    i+=1
  #echo (%* feeTaker)
  var result : BTCResponse
  var estimate = 0.0

  when defined(regTest):
    let sendingOptions = %* {"add_to_wallet" : false, "subtract_fee_from_outputs" : %* feeTaker}
    result = send(client,outputs, options = sendingOptions, feeRate = some(1.0))
    estimate = 1.0
  else:
    let sendingOptions = %* {"add_to_wallet" : false, "subtract_fee_from_outputs" : %* feeTaker}
    result = send(client, outputs, some(confTarget), options = sendingOptions)
    estimate = estimateSmartFee(client, confTarget, some(Economical)).resultObject["feerate"].getFloat()
  let rawHex = result.resultObject["hex"].getStr()
  let funded = fundrawtransaction(client, rawHex, %* {"fee_rate" : estimate})
  if funded.errorCode != RpcNoError:
    return E.err funded
  else:
    E.ok(funded)

proc submitBTC*(client : BTCClient, rawHex : string, txid : var string, failedSign : var bool) : Result[BTCResponse, BTCResponse] = 
  let signedTx = signRawTransactionWithWallet(client, rawHex)
  if signedTx.isErr:
    failedSign = true
    return err signedTx

  let isComplete = signedTx.resultObject["complete"].getBool()
  if not isComplete:
    failedSign = true
    return err signedTx
  
  let signedHex = signedTx.resultObject["hex"].getStr()
  let sendRawTx = sendRawTransaction(client, signedHex)

  if sendRawTx.isErr:
    return err sendRawTx

  result = ok sendRawTx
  txid = sendRawTx.resultObject.getStr()

proc sendBTC*(client : BTCClient, outputs : Table[string, float], confTarget : uint, walletPassword : options.Option[string] = none[string]()) :  options.Option[TX] =
 
  if walletPassword.isSome():
    let unlockAttempt = client.walletPassphrase(walletPassword.get(), 300)

  var tx = createTransaction(client, outputs, confTarget)
  if tx.isErr:
    echo "!!!!!"
    echo tx
    quit 1

  var failedSign = false
  var txid : string
  let rawHex = tx.get().resultObject["hex"].getStr()
  let submitted = submitBTC(client,  rawHex, txid, failedSign)

  #TODO: make better
  if submitted.isOK:
    return some queryTx(client, txid).get()

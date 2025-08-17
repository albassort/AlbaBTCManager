import puppy
import strformat
import strutils
import NimBTC
import Json
import pretty
import sequtils
import tables
import results
import std/options
import os
import libcurl
import std/base64
import times
import shared

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

proc makeTx*(client : BTCClient, tx : string) : TX =

  let txidAttemptGet = getTransaction(client, tx)
  let a = getTransaction(client, tx).resultObject
  
  result.txid = tx
  result.wTxId = a["wtxid"].getStr()
  result.amount = a["amount"].getFloat()
  result.confirmations = uint64 a["confirmations"].getInt()
  result.fee = abs a["fee"].getFloat()
  result.isAccepted = false

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

  #TODO: add possibility to reject fee estimate
  
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

  if submitted.isOK:
    return some makeTx(client, txid)

proc doStuff(url : string, postBody = "", doPost = false) =
  proc curlWriteFn(buffer: cstring, size: int, count: int,outstream: pointer): int =
    let outbuf = cast[ref string](outstream)
    outbuf[] &= buffer
    echo outbuf[]
    result = size * count
    
  let webData: ref string = new string
  let curl = easy_init()

  discard curl.easy_setopt(OPT_WRITEDATA, webData)
  discard curl.easy_setopt(OPT_WRITEFUNCTION, curlWriteFn)
  discard curl.easy_setopt(OPT_URL, url)

  let auth = readFile("/mnt/coding/QestBet/THB/subrepos/albaBTCPay/testing/lndir1/data/chain/bitcoin/regtest/admin.macaroon").toHex()

  var headers : Pslist 
  let authStr = &"Grpc-Metadata-macaroon: {auth}" 
  let setheaders = slist_append(headers, authStr)
  discard curl.easy_setopt(OPT_HTTPHEADER, setheaders);
  discard curl.easy_setopt(OPT_CAINFO, "/mnt/coding/QestBet/THB/subrepos/albaBTCPay/testing/lndir1/tls.cert");
  discard curl.easy_setopt(OPT_SSL_VERIFYPEER, 1);

  if doPost:
    discard curl.easy_setopt(OPT_POSTFIELDS, postBody)
    discard curl.easy_setopt(OPT_POSTFIELDSIZE, postBody.len)
    discard curl.easy_setopt(OPT_HTTPPOST, 1)
  else:
    discard curl.easy_setopt(OPT_HTTPGET, 1)



  let ret = curl.easy_perform()
  if ret == E_OK:
    echo(webData[])

when isMainModule:
  doStuff("https://localhost:8080/v1/invoices/subscribe")

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
import libcurl
import std/base64
import times
import streams
import locks

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
type 
  CurlMessageBuffer = object
    url : string
    buffer : seq[string]
    lock : Lock
    #amount of pending messages
    pCount : uint

type State = enum
  Poll, Reconfigure

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

proc initCurl(url : string, resultStream : ptr CurlMessageBuffer, postBody = "", doPost = false) : PCurl =

  proc curlWriteFn(buffer: cstring, size: int, count: int, outstream: pointer): int =

    let curlBuffer = cast[ptr CurlMessageBuffer](outstream)
    withLock curlBuffer[].lock:
      curlBuffer[].buffer.add($buffer)
      curlBuffer[].pCount += 1 
    return size * count
    
  let curl = easy_init()

  discard curl.easy_setopt(OPT_WRITEDATA, resultStream)
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

  return curl


const libname = "libcurl.so(|.4)"
proc multi_poll*(multi_handle: PM, skip : int, extra_nfds : uint32, timeout : int32, ret : var int32): Mcode{.cdecl,dynlib: libname, importc: "curl_multi_poll".}


when isMainModule:
  let baseUrl = "https://localhost:8080/v1/"
  let endPoints = @["invoices/subscribe", "channels/subscribe", "transactions/subscribe",
                    "gra1h/subscribe",  "state/subscribe", "peers/subscribe"]

  let endPointCount = endPoints.len

  # Keeping theme out of the table for memory safety
  var curlStreams : seq[CurlMessageBuffer]
  # Maybe bad if the pointer can be realloced and moved.
  var curlToStream : TableRef[PCurl, ptr CurlMessageBuffer] 
  var multi : PM
  var discon = 0

  proc initEndPoints() =
    for x in 0 .. curlStreams.high:
      deinitLock curlStreams[x].lock
    curlStreams.setLen(0)

    curlToStream = newTable[PCurl, ptr CurlMessageBuffer]()

    for endPoint in endPoints:
      var curlStream : CurlMessageBuffer
      initLock(curlStream.lock)
      curlStreams.add(curlStream)

      let point = addr curlStreams[curlStreams.high]
      let newCurl = initCurl(baseUrl & endPoint, point)
      curlToStream[newCurl] = point

    multi = multi_init()
    for curl in curlToStream.keys:
       doAssert multi.multi_add_handle(curl) == M_OK

  initEndPoints()
  quit 1
  var stillRunning : int32
  doAssert multi_perform(multi, stillRunning) == M_OK
  var count = 0
  var state {.goto.} = Reconfigure
  var ret : int32 = 0 
  case state
  of Poll:
    while stillRunning == endPointCount:

      doAssert multi_perform(multi, stillRunning) == M_OK
      let poll = multi_poll(multi, 0, 0, 1000, ret)

      for i in 0 .. curlStreams.high: 
        var curlStream = addr curlStreams[i]
        if curlStream[].pCount != 0:
          withLock curlStream[].lock:
            for message in curlStream[].buffer:
              echo (message, "MESSAGE")
            curlStream[].buffer.setLen(0)
            curlStream[].pCount = 0
        
      # if count == 10: 
      #   count = 0
      #   break
      count += 1
    # If that while loop isn't running, we can assume that 
    # something disconnected or is having an issue connecting
    state = Reconfigure
  of Reconfigure:


    var messagesLeft : int32 = 0

    #TODO: figure out why mullti_info_read doesn't work on my system 

    # doAssert multi_perform(multi, stillRunning) == M_OK
    # let poll = multi_poll(multi, 0, 0, 1000, ret)
    # echo poll
    # while true:
    #   let message = multi_info_read(multi, messagesLeft)
    #   echo (messagesLeft, cast[int](message))
    #   if message == nil: break
    #   echo message[].msg
    echo "Disonnection detected, disconnecting all endpoints and reconnecting"
    discon += 1
    for curl in curlToStream.keys:
      doAssert multi_remove_handle(multi, curl) == M_OK
      easy_cleanup(curl)
      initEndPoints()

    quit 1
    state = Poll
      # temp debug



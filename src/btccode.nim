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
type HalfBtcResponse* = object
  error* : RpcErrorCode
  errorMessage* : string
type E = Result[BTCResponse, BTCResponse]
#when isMainModule:
 # let tb1 = "tb1qds07ugl6ssw8zsefgdg9hxmwfqcn5c735"
  #print listreceivedbyaddress(client)

proc createTransaction*(client : BTCClient, outputs : Table[string, float], confTarget : uint) : Result[BTCResponse, BTCResponse] =
  ##  MUST BE SIGNED AFTER EXECUTION!!
  var feeTaker : seq[int]
  var i = 0
  for x in outputs.keys:
    feeTaker.add(i)
    i+=1
  echo (%* feeTaker)
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

#proc submitBTC() = 
#  signrawtransactionwithwallet

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

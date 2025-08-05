
import NimBTC
import Json
import pretty
import sequtils
import tables
import results
import std/options
import os
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

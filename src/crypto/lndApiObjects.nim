import json
import strutils
import jsony
import results

type
  MakeInvoiceResult* = object
    rHash : string
    paymentRequest* : string
    addIndex* : string
    paymentAddr* : string 
  CreateChannelResult* = object
    fundingTxidBytes* : string
    fundingTxStr* : string
    outputIndex* : int
  CloseChannelResult* = object
    txid* : string
    txidStr* : string
    outputIndex* : int
    feePerVByte : string
    localCloseTx : bool
  LndError* = object
    code : int
    message : int
    details : JsonNode

  ConnectionResult* = object
    status* : string
  PayInvoiceResult* = object
    paymentHash* : string
    value* : string
    creationDate* : string
    fee* : string
    paymentPreimage* : string
    valueSat* : string
    valueMsat* : string
    paymentRequest* : string
    status* : string
    feeSat* : string
    feeMsat* : string
    creationTimeNs* : string
    htlcs* : seq[HLTC]
    paymentIndex* : string
    failureReason* : string
    firstHopCustomRecords* : JsonNode

  InvoiceState* = enum
    Open = "OPEN", Closed = "CLOSED"

  HLTC* = object
    chanId : string
    amountMSat : int
    acceptHeight : int
    expiryHeight : int
    acceptTime : int
    expiryTime : int
    state : InvoiceState

  # To get the correct types
  InvoiceDataIner = object
    numSatoshis : string
    timestamp : string
    expiry : string
    numMsat : string
    cltvExpiry : string
    destination : string
    paymentHash: string
    description* : string
    descriptionHash : string
    fallbackAddr : string
    paymentAddr : string
    routeHints : JsonNode
    features : JsonNode
    blindedPaths : JsonNode

  InvoiceData* = object
    numSatoshis* : uint
    timestamp* : uint
    expiry* : uint
    numMsat* : uint
    cltvExpiry* : uint

    destination* : string
    paymentHash* : string
    description* : string
    descriptionHash* : string
    fallbackAddr* : string
    paymentAddr* : string

    routeHints* : JsonNode
    features* : JsonNode
    blindedPaths* : JsonNode

  NewLndAddress* = object
    address : string

proc parseString(a : string, b : var SomeUnsignedInt) = 
  b = parseUInt(a)
proc parseString(a : string, b : var SomeSignedInt) = 
  b = parseInt(a)

proc copyCorrectTypes*[A;B](a : A, b :var B) = 
  for x, y in fieldPairs(a):
    for x1, y1 in fieldPairs(b):
      when x == x1:
        when y is string and y1 is not string:
          parseString(y, y1)
        else:
          y1 = y
  
proc parseInvoiceData*(a : string) : InvoiceData = 
  let parsed = a.fromJson(InvoiceDataIner)
  copyCorrectTypes(parsed, result)

const errKeys = @["code", "message", "details"]

proc tempJsonConverter*[A](a : JsonNode, b : typedesc[A]) : A =
  # TODO: this is really bad and needs to be fixed but implementing a change would need to recurisevely change the name of each key, and normalize between the fieldpairs of the object

  ($a).fromJson(b)

proc parseLND*[A](str : string, b : typedesc[A]) : Result[A,LndError] =

  let parsed = parseJson(str)
  if parsed.contains("error"):
    return err tempJsonConverter(parsed["error"], LndError)
  else:
    for key in errKeys:
      if parsed.contains(key):
        return err tempJsonConverter(parsed, LndError)

  return ok str.fromJson(A)


proc parseLND*[A](str : string, parse : proc(a: string) : A) : Result[A,LndError] =

  let parsed = parseJson(str)
  if parsed.contains("error"):
    return err tempJsonConverter(parsed["error"], LndError)
  else:
    for key in errKeys:
      if parsed.contains(key):
        return err tempJsonConverter(parsed, LndError)

  return ok parse(str)


import json
import tables
import base64
import algorithm
import strutils
import jsony
import results
import ../shared
import libcurl

type
  LndAddInvoiceResult* = object
    rHash : string
    paymentRequest* : string
    addIndex* : string
    paymentAddr* : string 
  LndAddChannelResult* = object
    fundingTxidBytes* : string
    fundingTxStr* : string
    outputIndex* : int
  CloseChannelResult* = object
    txid* : string
    txidStr* : string
    outputIndex* : int
    feePerVByte : string
    localCloseTx : bool
  LndError* = object of AlbaBTCException
    code* : int
    message* : string
    details* : JsonNode
    libcurlError* : Code

  LndConnectionResult* = object
    status* : string
  LndPayInvoiceResult* = object
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
  LndInvoiceDataIner = object
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
  LndInvoiceData* = object
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

  OpenChannel* = object
    active* : bool
    remotePubkey* : string
    channelPoint* : string
    chanId* : string
    capacity* : string
    localBalance* : string
    remoteBalance* : string
    commitFee* : string
    commitWeight* : string
    feePerKw* : string
    unsettledBalance* : string
    totalSatoshisSent* : string
    totalSatoshisReceived* : string
    numUpdates* : string
    pendingHtlcs* : seq[HLTC]            # original was []
    csvDelay* : int                  # original was 144 (number)
    private* : bool
    initiator* : bool
    chanStatusFlags* : string
    localChanReserveSat* : string
    remoteChanReserveSat* : string
    staticRemoteKey* : bool
    commitmentType* : string
    lifetime* : string
    uptime* : string
    closeAddress* : string
    pushAmountSat* : string
    thawHeight* : int                # original was 0 (number)
    zeroConf* : bool
    zeroConfConfirmedScid* : string
    peerAlias* : string
    peerScidAlias* : string
    memo* : string
    customChannelData* : string
  ChannelsQuery* = enum
    ActiveOnly, InactiveOnly, Both
  LndNewAddress* = object
    address : string

proc parseString(a : string, b : var SomeUnsignedInt) = 
  b = parseUInt(a)
proc parseString(a : string, b : var SomeSignedInt) = 
  b = parseInt(a)

proc reverseBase64*(a : string) : string =
  let raw = a.decode().reversed()
  result = cast[string](raw).toHex().toLowerAscii()

proc copyCorrectTypes*[A;B](a : A, b :var B) = 
  for x, y in fieldPairs(a):
    for x1, y1 in fieldPairs(b):
      when x == x1:
        when y is string and y1 is not string:
          parseString(y, y1)
        else:
          y1 = y
  
proc parseLNDInvoiceData*(a : string) : LndInvoiceData = 
  let parsed = a.fromJson(LndInvoiceDataIner)
  copyCorrectTypes(parsed, result)

proc parseOpenChannel*(a : string) : LndAddChannelResult =

  result = a.fromJson(LndAddChannelResult)
  result.fundingTxStr = reverseBase64(result.fundingTxidBytes)

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

proc parseLNDChannelsList*(a : string) : seq[OpenChannel] = 
  # I feel like this is a clever solution
  let inter = a.fromJson(Table[string, seq[OpenChannel]])
  result = inter["channels"]
  

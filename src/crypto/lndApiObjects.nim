import json
import tables
import base64
import algorithm
import strutils
import jsony
import results
import ../shared
import libcurl
import options

type
  LndAddInvoiceResult* = object
    rHash* : string
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
  LndConnectionResult* = object
    status* : string
  lndPayInvoiceImter* = object
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
  LndPayInvoiceResult* = object
    paymentHash* : string
    value* : uint64
    creationDate* : uint64
    fee* : uint64
    paymentPreimage* : string
    valueSat* : uint64
    valueMsat* : uint64
    paymentRequest* : string
    status* : string
    feeSat* : uint64
    feeMsat* : string
    creationTimeNs* : string
    htlcs* : seq[HLTC]
    paymentIndex* : int
    failureReason* : string
    firstHopCustomRecords* : JsonNode

  InvoiceState* = enum
    Open = "OPEN", Closed = "CLOSED"

  HLTCHops* = object
    chanId* : string
    pubKey* : string
    amtToForward : string
    fee : string
    expiry : uint64
    amtToForwardMsat : string


    # There is more but because of the incompotence of LND developers they are encoding them as strings, lets just not use them.
    # Keys under each hops[] entry
    # chan_id
    # chan_capacity
    # amt_to_forward
    # fee
    # expiry
    # amt_to_forward_msat
    # fee_msat
    # pub_key
    # tlv_payload
    # mpp_record (object, may be null)
    # amp_record (null here)
    # custom_records (object)
    # metadata
    # blinding_point
    # encrypted_data
    # total_amt_msat
  HLTCRoute* = object
    totalTimeLock* : uint64
    totalFees* : string
    totalAmt* : string
    hops* : seq[HLTCHops]
  HLTC* = object
    chanId : string
    amountMSat : int
    acceptHeight : int
    expiryHeight : int
    acceptTime : int
    expiryTime : int
    state : InvoiceState
    route : options.Option[HLTCRoute]
  # To get the correct types
  LndInvoiceDataIner* = object
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

proc initLndError(a : JsonNode) : AlbaBTCException =
  var inter = a
  inter["etype"] = %* "LND"
  result = inter.to(AlbaBTCException)


proc lndIsErr*(a : string) : Result[JsonNode, AlbaBTCException] = 

  let parsed = parseJson(a)
  if parsed.contains("error"):
    return err initLndError(parsed["error"])
  else:
    for key in errKeys:
      if parsed.contains(key):
        return err initLndError(parsed)


  return ok parsed



proc parseLND*[A](str : string, b : typedesc[A]) : Result[A,AlbaBTCException] =

  let parsed = parseJson(str)
  if parsed.contains("error"):
    return err initLndError(parsed)
  else:
    for key in errKeys:
      if parsed.contains(key):
        return err initLndError(parsed)

  return ok str.fromJson(A)


proc parseLND*[A](str : string, parse : proc(a: string) : A) : Result[A,AlbaBTCException] =

  let parsed = parseJson(str)
  if parsed.contains("error"):
    return err initLndError(parsed)
  else:
    for key in errKeys:
      if parsed.contains(key):
        return err initLndError(parsed)

  return ok parse(str)

proc parseLNDChannelsList*(a : string) : seq[OpenChannel] = 
  # I feel like this is a clever solution
  let inter = a.fromJson(Table[string, seq[OpenChannel]])
  result = inter["channels"]
  
proc parseLNDPaymentInvoice*(a : string) : LndPayInvoiceResult =
  let parsed = a.fromJson(lndPayInvoiceImter)
  copyCorrectTypes(parsed, result)

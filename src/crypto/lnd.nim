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
import jsony


# Here onward is LND
type 
  ChannelEventType = enum
    INACTIVE = "INACTIVE_CHANNEL"
    ACTIVE = "ACTIVE_CHANNEL"
    CLOSED = "CLOSED_CHANNEL"
    PENDING = "PENDING_OPEN_CHANNEL"
    OPEN = "OPEN_CHANNEL"
    RESOLVED = "FULLY_RESOLVED_CHANNEL"

  ActiveChannel = object
    fundingTxidBytes : string
    outputIndex : int
  InactiveChannel = object
    fundingTxidBytes : string
    outputIndex : int
  ResolvedChannel = object
    fundingTxidBytes : string
    outputIndex : int
  PendingChannel = object 
    txid : string
    outputIndex : int
    freePerVbyte : int
    localCloseTx : bool
  OpenChannel = object
    active : bool
    remotePubkey : string
    channelPoint : string
    chanId : string
    capacity : string
    localBalance : string
    remoteBalance : string
    commitFee : string
    commitWeight : string
    feePerKw : string
    unsettledBalance : string
    totalSatoshisSent : string
    totalSatoshisReceived : string
    numUpdates : string
    pendingHtlcs : seq[HLTC]            # original was []
    csvDelay : int                  # original was 144 (number)
    private : bool
    initiator : bool
    chanStatusFlags : string
    localChanReserveSat : string
    remoteChanReserveSat : string
    staticRemoteKey : bool
    commitmentType : string
    lifetime : string
    uptime : string
    closeAddress : string
    pushAmountSat : string
    thawHeight : int                # original was 0 (number)
    zeroConf : bool
    zeroConfConfirmedScid : string
    peerAlias : string
    peerScidAlias : string
    memo : string
    customChannelData : string

  ClosedChannel = object
    channelPoint : string
    chanId : string
    chainHash : string
    closingTxHash : string
    remotePubkey : string
    capacity : string
    closeHeight : int
    settledBalance : string
    timeLockedBalance : string
    closeType : string
    openInitiator : string
    closeInitiator : string
    # i dont know these typues yet
    # resolutions : seq[]
    # aliasScids : seq[]
    zeroConfConfirmedScid : string
    customChannelData : string

    # aliasScids : seq[]              
  ChannelEvent = object
    case event: ChannelEventType
    of PENDING:
      pendingOpenChannel : PendingChannel
    of ACTIVE:
      activeChannel : ActiveChannel
    of INACTIVE:
      inactiveChannel : InactiveChannel
    of CLOSED:
      closedChannel : ClosedChannel
    of OPEN:
      openChannel : OpenChannel
    of RESOLVED:
      fullyResolvedCHannel : ResolvedChannel 

  InvoiceState = enum
    Open = "OPEN", Closed = "CLOSED"

  HLTC* = object
    chanId : string
    amountMSat : int
    acceptHeight : int
    expiryHeight : int
    acceptTime : int
    expiryTime : int
    state : InvoiceState
  Invoice* = object
    memo : string
    value : int
    settled : bool
    expiry : int
    state : InvoiceState
    paymentRequest : string
    amtPaidSat : int
    chanId : string
    htlcs : seq[HLTC]


type
  EventType =  enum
    InvoiceEvent, Channels, Transactions, Peers, StateUpdate
  OutputDetail = object
    outputType: string
    address: string
    pkScript: string
    outputIndex: string   # string in JSON
    amount: string        # string in JSON
    isOurAddress: bool

  PreviousOutpoint = object
    outpoint: string
    isOurOutput: bool

  TxEvent = object
    txHash: string
    amount: string
    numConfirmations: int
    blockHash: string
    blockHeight: int
    timeStamp: string      # string in JSON
    totalFees: string
    destAddresses: seq[string]
    outputDetails: seq[OutputDetail]
    rawTxHex: string
    label: string
    previousOutpoints: seq[PreviousOutpoint]
  PeerEvents = enum
    ONLINE = "PEER_ONLINE", OFFLINE = "PEER_OFFLINE"
  PeerEvent = object
    pubKey : string
    event : PeerEvents
  StateEvent = object
    state : string 
  SubscribedEvent* = object
    case source* : EventType
    of InvoiceEvent:
      invoice : Invoice
    of Channels:
      channel : ChannelEvent
    of Transactions:
      tx : TxEvent
    of Peers:
      peer : PeerEvent 
    of StateUpdate:
      state : StateEvent 

type 
  CurlMessageBuffer = object
    url : string
    buffer : seq[string]
    lock : Lock
    #amount of pending messages
    pCount : uint
    reading : bool
    jsonBuffer : string
  SubscribeState = enum
    Poll, Reconfigure


      

proc initPeerEvent(a : string) : PeerEvent = 
  var parsed = (fromJson a)["result"]
  let event = parsed["type"]
  # We need to rename type to event because... this is easier
  parsed["event"] = event
  result = ($parsed).fromJson(PeerEvent)


proc initChannel(a : string) : ChannelEvent =
  var parsed = (fromJson a)["result"]
  let event = parsed["type"]
  # We need to rename type to event because... this is easier
  parsed["event"] = event
  result = ($parsed).fromJson(ChannelEvent)

proc initTransaction(a : string) : TxEvent = 
  var parsed = (fromJson a)["result"]
  # We need to rename type to event because... this is easier
  result = ($parsed).fromJson(TxEvent)

proc initState(a : string) : StateEvent = 
  result.state = (fromJson a)["result"]["state"].getStr()

proc initInvoice(a : string) : Invoice = 
  var parsed = (fromJson a)["result"]
  # We need to rename type to event because... this is easier
  result = ($parsed).fromJson(Invoice)



proc initCurl(url : string, resultStream : ptr CurlMessageBuffer, postBody = "", doPost = false) : PCurl =


  proc curlWriteFn(buffer: cstring, size: int, count: int, outstream: pointer): int =

    let curlBuffer = cast[ptr CurlMessageBuffer](outstream)
    let strBuff = $buffer
    let atEnd = (strBuff)[^3 .. ^1]  == "\n\r\n"
    let reading = curlBuffer[].reading
    echo (atEnd, reading)
    
    withLock curlBuffer[].lock:
      if reading:
        let bstring = curlBuffer.jsonBuffer
        let current = bstring & strBuff
        if atEnd: 
          curlBuffer[].buffer.add(current)
          curlBuffer[].pCount += 1
          curlBuffer[].reading = false
        else:
          curlBuffer.jsonBuffer = current
      else:
        if atEnd:
          curlBuffer[].buffer.add(strBuff)
          curlBuffer[].pCount += 1
        else:
          curlBuffer.jsonBuffer = strBuff
          curlBuffer[].reading = true

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


iterator getUpdates(root : string) : SubscribedEvent = 
  let ep = {
    "invoices/subscribe" : InvoiceEvent,
    "channels/subscribe" : Channels,
    "transactions/subscribe" : Transactions,
    "state/subscribe" : StateUpdate,
    "peers/subscribe" : Peers
  }.toTable()

  var endPoints : seq[string]
  var epToType = initTable[string, EventType]()

  for e, et in ep.pairs:
    let url = root & e
    endPoints.add(url) 
    epToType[url] = et

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

    for url in endPoints:
      var curlStream : CurlMessageBuffer
      curlStream.url = url
      initLock(curlStream.lock)
      curlStreams.add(curlStream)

      let point = addr curlStreams[curlStreams.high]

      let newCurl = initCurl(url, point)
      curlToStream[newCurl] = point

    multi = multi_init()
    for curl in curlToStream.keys:
       doAssert multi.multi_add_handle(curl) == M_OK

  initEndPoints()

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
              let responseType = epToType[curlStream[].url]
              echo message
              echo responseType
              case responseType
              of InvoiceEvent:
                let inter = initInvoice(message) 
                yield SubscribedEvent(source : responseType, invoice : inter)
              of Channels:
                let inter = initChannel(message)
                yield SubscribedEvent(source : responseType, channel : inter)
              of Transactions:
                let inter = initTransaction(message)
                yield SubscribedEvent(source : responseType, tx : inter)
              of Peers:
                let inter = initPeerEvent(message)
                yield SubscribedEvent(source : responseType, peer : inter)
              of StateUpdate:
                let inter = initState(message)
                yield SubscribedEvent(source : responseType, state : inter)
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

    if discon == 3:
      echo "too many dissonnections!"
      quit 1

    discon += 1
    for curl in curlToStream.keys:
      doAssert multi_remove_handle(multi, curl) == M_OK
      easy_cleanup(curl)
      initEndPoints()

    state = Poll
      # temp debug

when isMainModule:

  let baseUrl = "https://localhost:8080/v1/"
  for event in getUpdates(baseUrl):
    echo event


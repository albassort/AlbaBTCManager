import puppy
import uri
import results
import algorithm
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
import base64
import ./lndApiObjects


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

  InvoiceSubscribe* = object
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
      invoice :InvoiceSubscribe 
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


proc initChannelEvent(a : string) : ChannelEvent =
  var parsed = (fromJson a)["result"]
  let event = 
    if not parsed.contains("type"):
      parsed.keys.toSeq[0].toUpperAscii()
   else:
      parsed["type"].getStr()
  
  # We need to rename type to event because... this is easier
  parsed["event"] = %* event
  result = ($parsed).fromJson(ChannelEvent)

proc initTransaction(a : string) : TxEvent = 
  var parsed = (fromJson a)["result"]
  # We need to rename type to event because... this is easier
  result = ($parsed).fromJson(TxEvent)

proc initState(a : string) : StateEvent = 
  result.state = (fromJson a)["result"]["state"].getStr()

proc initInvoice(a : string) : InvoiceSubscribe = 
  var parsed = (fromJson a)["result"]
  # We need to rename type to event because... this is easier
  result = ($parsed).fromJson(InvoiceSubscribe)

proc curlStreamRead(buffer: cstring, size: int, count: int, outstream: pointer): int =

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


proc initCurlCore(url : string, callbackPtr : pointer, 
                writeFn : proc(a : cstring, b, c : int, d: pointer,): int,
                userHeaders : TableRef[string, string] = nil
                ) : PCurl =
    
  let curl = easy_init()

  discard curl.easy_setopt(OPT_WRITEDATA, callbackPtr)
  discard curl.easy_setopt(OPT_WRITEFUNCTION, writeFn)
  discard curl.easy_setopt(OPT_URL, url)

  let auth = readFile("/mnt/coding/QestBet/THB/subrepos/albaBTCPay/testing/lndir1/data/chain/bitcoin/regtest/admin.macaroon").toHex()

  var headers : Pslist 
  let authStr = &"Grpc-Metadata-macaroon: {auth}" 
  var setheaders = slist_append(headers, authStr)
  if userHeaders != nil:
    for key,val in userHeaders.pairs:
      let headerstr = &"{key}: {val}" 
      echo headerstr
      setheaders = slist_append(setheaders, headerstr)

  discard curl.easy_setopt(OPT_HTTPHEADER, setheaders)
  discard curl.easy_setopt(OPT_CAINFO, "/mnt/coding/QestBet/THB/subrepos/albaBTCPay/testing/lndir1/tls.cert");
  discard curl.easy_setopt(OPT_SSL_VERIFYPEER, 1);

  return curl

proc normalCurlRead(buffer: cstring, size: int, count: int, outstream: pointer): int =

  let outstream = cast[ptr string](outstream)
  let stringy = $buffer
  outstream[] = outstream[] & stringy
  echo outstream[]  

  if stringy[^3 .. ^1]  == "\n\r\n":
    return 0

  return size * count


proc initCurlGet(url : string, messageBuffer : ptr string) : PCurl =
  var curl =  initCurlCore(url, messageBuffer, normalCurlRead)
  discard curl.easy_setopt(OPT_HTTPGET, 1)
  return curl


proc initCurlPost(url : string, messageBuffer : ptr string, body : string, resultStr : cstring, alternateVerb = "") : PCurl =

  let resultStr = cast[cstring](alloc0(body.len+1))
  if body.len != 0:
    copyMem(resultStr, addr body[0], body.len)

  echo body
  echo resultStr
  echo ($resultStr).len
  echo body.len

  var table = newTable[string, string]()
  table["Content-Type"] = "application/json"

  var curl =  initCurlCore(url, messageBuffer, normalCurlRead, table)

  if alternateVerb != "":
    discard curl.easy_setopt(OPT_CUSTOMREQUEST, alternateVerb)
  else:
    discard curl.easy_setopt(OPT_HTTPPOST, 1)

  discard curl.easy_setopt(OPT_POSTFIELDS, resultStr)
  discard curl.easy_setopt(OPT_POSTFIELDSIZE, body.len)
  
  return curl


proc initCurlStream(url : string, stream : ptr CurlMessageBuffer) : PCurl =
  var curl =  initCurlCore(url, stream, curlStreamRead)
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

      let newCurl = initCurlStream(url, point)
      curlToStream[newCurl] = point

    multi = multi_init()
    for curl in curlToStream.keys:
       let res = multi.multi_add_handle(curl) 
       echo res 
       doAssert res == M_OK

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
                let inter = initChannelEvent(message)
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

proc makeInvoice*(memo : string, amtSat : int64, validDuration : int64 = 0, isAmp : bool = true) : JsonNode =
  result = newJObject()
  result["memo"] = %* memo
  result["value"] = %* amtSat
  result["expiry"] = %* validDuration
  result["is_amp"] = %* isAmp


proc payInvoice*(paymentRequest : string, amp = false, amt : uint64 = 0) : JsonNode =
  # TOOD:  figure out how "cancelable" works.
  result = newJObject()
  result["payment_request"] = %* paymentRequest 
  result["amt"] = %* amt
  result["amp"] = %* amp


proc makeChannelRequest*(pubKey : string, localFundingAmtSat : uint, closeAddress : string = "", private = false, memo : string = "", pushSat : uint64 = 0, targetConf = 6) : JsonNode =

  result = newJObject()
  result["node_pubkey_string"] = %* pubKey
  result["local_funding_amount"] = %* localFundingAmtSat
  if closeAddress != "":
    result["close_address"] = %* closeAddress
  result["target_conf"] = %* targetConf

  if memo != "":
    result["memo"] = %* memo

  result["push_sat"] = %* pushSat
  result["private"] = %* private

proc addPeer*(pubkey: string, address : string, permanent : bool = true, timeout : uint = 20) : JsonNode =

  result = newJObject()


  let lndaddr = %* { 
     "pubkey": pubKey,
     "host" : address
  } 

  result["addr"] = %*  lndaddr 
  result["perm"] = %* permanent
  result["timeout"] = %* timeout

#TODO: add hold

proc closeChannel*(force : bool, deliveryAddress : string = "", targetConf : uint = 6) : JsonNode = 
  ## We do not wait because we are already listening to the channel streamas. Otherwise we would just put it in a multi and kill it after we get our first message.
  result = newJObject()
  result["force"]  = %* force

  if deliveryAddress != "":
    result["delivery_address"]  = %* force

  result["target_conf"]  = %* targetConf
  result["no_wait"] = %* false

proc reverseBase64(a : string) : string =
  let raw = a.decode().reversed()
  result = cast[string](raw).toHex().toLowerAscii()

####

proc createInvoice() : Result[MakeInvoiceResult, LndError] =
  var messageBuf : string
  var resultStr : cstring
  let invoice = makeInvoice("this is a test", 5000)
  let invoices = "https://localhost:8080/v1/invoices"
  let curlGet = initCurlPost(invoices, addr messageBuf, $invoice, resultStr)
  echo curlGet.easy_perform()
  free(resultStr)
  messageBuf.parseLND(MakeInvoiceResult)


proc openChannel() : Result[CreateChannelResult, LndError] = 

  let invoices = "https://localhost:8080/v1/channels"
  var messageBuf : string
  var resultStr : cstring


  let pubkey = "03f23d05bcb3bc73b08dea0d98c56f9bfe2d6a83b7239aa4a380a68433c30097d5"
  let thisIsAChannel = makeChannelRequest("03f23d05bcb3bc73b08dea0d98c56f9bfe2d6a83b7239aa4a380a68433c30097d5", 20000)

  let curlGet = initCurlPost(invoices, addr messageBuf, $thisIsAChannel, resultStr)

  echo curlGet.easy_perform()
  free(resultStr)

  result = messageBuf.parseLND(CreateChannelResult)

  #The endianness is backwards by defualt out of sheer spite.

proc makeAndCloseChannel() : Result[CloseChannelResult, LndError] = 
  var messageBuf : string
  var resultStr : cstring
  let newChannelAtmp = openChannel()
  let newChannel = 
    if newChannelAtmp.isErr:
      echo "Aaa"
      quit 1
    else:
      newChannelAtmp.get() 

  echo "do the confirm, manually lol"
  sleep 10000

  let close = closeChannel(true)
  let txStr = reverseBase64 newChannel.fundingTxidBytes

  let closePath = &"https://localhost:8080/v1/channels/{txStr}/{newChannel.outputIndex}"

  let curlGet = initCurlPost(closePath, addr messageBuf, $close, resultStr, "DELETE")


  echo curlGet.easy_perform()
  echo "exited"
  free(resultStr)
  echo " print"

  let responseJson = parseJson(messageBuf)["result"]["close_pending"]
  result = ($responseJson).parseLND(CloseChannelResult)
  print result

proc payTest() : Result[PayInvoiceResult, LndError] =

  var messageBuf : string
  var resultStr : cstring
  let url = "https://localhost:8080/v2/router/send"

  let payReq = "lnbcrt60u1p5vympupp59sk09gpwqd9pkwechregpjt992sd3n7qr28sunl0fe8ypz5xk9cqdqqcqzzsxqyz5vqsp5zy73xujyw4ganp6aaptzuvm8g84g8fpcxj4pt788s6exvehcd0rq9qxpqysgqhhhms3fvv9u3s5x2zgx58vdc4rlkeul5k9vhrqcp9v6zaeskpgc3pphtxrh2gw7379wzsecmq5l2x3mmjv7e83hh4hmn3nlpa0g3dsgpn5k3ze"

  let toPay = payInvoice(payReq, amt=5000)

  let curlGet = initCurlPost(url, addr messageBuf, $toPay, resultStr)

  echo curlGet.easy_perform()
  free(resultStr)
  ($(parseJson(messageBuf)["result"])).parseLND(PayInvoiceResult)

proc connectToPeer() : Result[ConnectionResult, LndError] =  
  var messageBuf : string
  var resultStr : cstring
  let url = "https://localhost:8080/v1/peers"

  let pubkey = "03f23d05bcb3bc73b08dea0d98c56f9bfe2d6a83b7239aa4a380a68433c30097d5"
  let ip = "127.0.0.1:9736"
  let ep = addPeer(pubkey, ip)

  let curlGet = initCurlPost(url, addr messageBuf, $ep, resultStr)
  echo curlGet.easy_perform()
  free(resultStr)
  result = messageBuf.parseLND(ConnectionResult)


proc disconnectPeer() : Result[ConnectionResult, LndError] =
  var messageBuf : string
  var resultStr : cstring

  let pubkey = "03f23d05bcb3bc73b08dea0d98c56f9bfe2d6a83b7239aa4a380a68433c30097d5"
  let url = &"https://localhost:8080/v1/peers/{pubkey}"

  let curlGet = initCurlPost(url, addr messageBuf, "", resultStr, "DELETE")
  echo curlGet.easy_perform()
  free(resultStr)
  result = messageBuf.parseLND(ConnectionResult)

proc getInvoice()  = 
  var messageBuf : string

  let invoice = "lnbcrt60u1p5vyaz4pp54k0s55tnac23y0a5wrvxf4l8796secg8hyntur4njfrn09xuvsfqdqqcqzzsxqyz5vqsp5e4u2rgmh7glhh6va0eg4p27glr86uhksewr6rl0p90gtqq7aqzuq9qxpqysgqv9q48tjl42248292s924de4c0qtaapm8xnuas29x6ryg49faewfzqupjsfakfwuzwjccaq0mtt66u33n0aguk2q465lgkmjq8u4xtvgqdp7xdj"
  # let encoded = encodeQuery(@[("r_hash=", invoice)])
  # echo encoded
  let url = &"https://localhost:8080/v1/payreq/{invoice}"

  echo url
  let curlGet = initCurlGet(url, addr messageBuf)
  echo curlGet.easy_perform()

  echo parseLND(messageBuf, parseInvoiceData)


proc makeNewAddress() : Result[NewLndAddress, LndError] =
  var messageBuf : string

  # bech32
  let url = &"https://localhost:8080/v1/newaddress?type=0"
  let curlGet = initCurlGet(url, addr messageBuf)
  echo curlGet.easy_perform()
  echo messageBuf.parseLND(NewLndAddress)

  result = messageBuf.parseLND(NewLndAddress)

when isMainModule:
  echo makeNewAddress()

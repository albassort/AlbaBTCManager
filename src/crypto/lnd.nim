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
export results
export lndApiObjects
import ../shared

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
      lndOpenChannel : OpenChannel
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
#template mcodeToLndError(a : Mcode) =
template handleCurl(a : Code)  =
  if a != E_OK and a != E_WRITE_ERROR:
    return err libCurlError(a)

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
  #echo outstream[]  

  if stringy[^3 .. ^1]  == "\n\r\n":
    outstream[] = outstream[].split("\n")[0]
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
let lndUrl = createShared(string, sizeof(string))
proc setLNDUrl*(a : string) = 
  lndUrl[] = a

proc makeInvoice*(memo : string, amtSat : uint64, validDuration : int64 = 0, isAmp : bool = true) : JsonNode =
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


proc makeOpenChannel*(pubKey : string, localFundingAmtSat : uint, closeAddress : string = "", private = false, memo : string = "", pushSat : uint64 = 0, targetConf = 6) : JsonNode =

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


proc lndAddInvoice*(memo : string, amtSat : uint64, validDuration = 0, isAmp : bool = false) : Result[LndAddInvoiceResult, AlbaBTCException] =
  var messageBuf : string
  var resultStr : cstring
  let invoice = makeInvoice(memo, amtSat, validDuration, isAmp)
  let invoices = &"{lndUrl[]}/v1/invoices"
  let curlGet = initCurlPost(invoices, addr messageBuf, $invoice, resultStr)
  let curlResult = curlGet.easy_perform()
  free(resultStr)

  return messageBuf.parseLND(LndAddInvoiceResult)


proc lndOpenChannel*(pubKey : string, localFundingAmtSat : uint, closeAddress : string = "", private = false, memo : string = "", pushSat : uint64 = 0, targetConf = 6) : Result[LndAddChannelResult, AlbaBTCException] = 

  let channelEndpoint = &"{lndUrl[]}/v1/channels"
  var messageBuf : string
  var resultStr : cstring


  let thisIsAChannel = makeOpenChannel(pubKey, localFundingAmtSat, closeAddress, private, memo, pushSat, targetConf)

  let curlGet = initCurlPost(channelEndpoint, addr messageBuf, $thisIsAChannel, resultStr)

  let curlResult = curlGet.easy_perform()
  free(resultStr)
  handleCurl curlResult
  messageBuf.parseLND(parseOpenChannel)
  #The endianness is backwards by defualt out of sheer spite.

proc lndCloseChannel*(txStr : string, outputIndex : int, deliveryAddress : string = "", targetConf : uint = 6, force = false) : Result[CloseChannelResult, AlbaBTCException] = 
  var messageBuf : string
  var resultStr : cstring
  let closePath = &"{lndUrl[]}/v1/channels/{txStr}/{outputIndex}"

  let close = closeChannel(force, deliveryAddress, targetConf)

  let curlGet = initCurlPost(closePath, addr messageBuf, $close, resultStr, "DELETE")
  let curlResult = curlGet.easy_perform()
  handleCurl curlResult
  free(resultStr)

  let responseJson = parseJson(messageBuf)["result"]["close_pending"]
  result = ($responseJson).parseLND(CloseChannelResult)

proc lndPayInvoiceImp*(payReq : string, amt : uint64 = 0, amp = false) : Result[LndPayInvoiceResult, AlbaBTCException] =

  var messageBuf : string
  var resultStr : cstring
  let url = &"{lndUrl[]}/v2/router/send"

  let toPay = payInvoice(payReq, amp, amt)

  let curlGet = initCurlPost(url, addr messageBuf, $toPay, resultStr)

  let curlResult = curlGet.easy_perform()
  free(resultStr)
  handleCurl curlResult

  let resultInter = lndIsErr messagebuf
  if resultInter.isErr:
    return err resultInter.error()

  return ok ($(resultInter.get()["result"])).parseLNDPaymentInvoice()
  

proc lndConnectPeer*(pubkey, ip : string) : Result[LndConnectionResult, AlbaBTCException] =  
  var messageBuf : string
  var resultStr : cstring
  let url = &"{lndUrl[]}/v1/peers"
  let ep = addPeer(pubkey, ip)

  let curlGet = initCurlPost(url, addr messageBuf, $ep, resultStr)
  let curlResult = curlGet.easy_perform()
  free(resultStr)
  handleCurl curlResult
  result = messageBuf.parseLND(LndConnectionResult)


proc lndDisconnectPeer*(pubkey : string) : Result[LndConnectionResult, AlbaBTCException] =
  var messageBuf : string
  var resultStr : cstring

  let url = &"{lndUrl[]}/v1/peers/{pubkey}"

  let curlGet = initCurlPost(url, addr messageBuf, "", resultStr, "DELETE")
  let curlResult = curlGet.easy_perform()
  free(resultStr)
  handleCurl curlResult
  result = messageBuf.parseLND(LndConnectionResult)

proc lndGetInvoiceInfo*(invoice : string) : Result[LndInvoiceData, AlbaBTCException] = 
  var messageBuf : string

  # let encoded = encodeQuery(@[("r_hash=", invoice)])
  # echo encoded

  let url = &"{lndUrl[]}/v1/payreq/{invoice}"
  echo url
  let curlGet = initCurlGet(url, addr messageBuf)
  let curlResult = curlGet.easy_perform()
  handleCurl curlResult
  
  result =  messageBuf.parseLND(parseLNDInvoiceData)

proc lndNewAddress() : Result[LndNewAddress, AlbaBTCException] =
  var messageBuf : string

  # bech32
  let url = &"{lndUrl[]}/v1/newaddress?type=0"
  let curlGet = initCurlGet(url, addr messageBuf)
  let curlResult = curlGet.easy_perform()
  handleCurl curlResult
  return messageBuf.parseLND(LndNewAddress)

proc lndListPayments() : seq[LndPayInvoiceResult] =
  var messageBuf : string

  let url = &"{lndUrl[]}/v1/payments"
  let curlGet = initCurlGet(url, addr messageBuf)
  let curlResult = curlGet.easy_perform()
  # when i do it the normal way theres an issue sorry future me.

  echo messageBuf
  let inter = ($(messageBuf.parseJson()["payments"])).fromJson(seq[lndPayInvoiceImter])


  for x in inter:
    var def = default(LndPayInvoiceResult)
    copyCorrectTypes(x, def)
    result.add(def)
  # echo messageBuf.parseLND(LndNewAddress)
  # result = messageBuf.parseLND(LndNewAddress)




proc lndGetChannelBalance*() =
  var messageBuf : string

  let url = &"{lndUrl[]}/v1/balance/channels"
  let curlGet = initCurlGet(url, addr messageBuf)
  let curlResult = curlGet.easy_perform()
  echo messageBuf
  # echo messageBuf.parseLND(LndNewAddress)
  # result = messageBuf.parseLND(LndNewAddress)

proc lndListChannels*(mode : ChannelsQuery = ActiveOnly) : Result[seq[OpenChannel], AlbaBTCException] =
  
  let url = 
    case mode
    of InactiveOnly:
      &"{lndUrl[]}/v1/channels?inactive_only=true"
    of ActiveOnly:
      &"{lndUrl[]}/v1/channels?active_only=true"
    of Both:
      &"{lndUrl[]}/v1/channels"

  var messageBuf : string
  let curlGet = initCurlGet(url, addr messageBuf)
  
  let curlResult = curlGet.easy_perform()
  handleCurl curlResult

  return messageBuf.parseLND(parseLNDChannelsList)


when isMainModule:
  setLNDUrl("https://localhost:8080")
  # echo "PAY INVOICE
  # let paid = lndPayInvoiceImp("lnbcrt50u1p5v33azpp58nav0fwgwtdtm2368ests740l5nxtsycw95t99qet8cl36arp7asdqqcqzzsxqyz5vqsp5s9a42mlysm7kyflrjf2akqvrjxcc3vwkalql72zqg9z8e6zyslms9qxpqysgqqsd0xzwh2v6r7e9ym9axulr906adjm9c9et8rgg42ehdytzvpkwqrcw2h2r6erawk9tqzmdr3q8qwpu0m6atqzm3rmfegt74w8madtcqntsvnf").get()
  # print paid
  echo lndListPayments()
#lndListChannels()

  #echo lndOpenChannel()
  #lndGetChannelBalance()
  # echo lndConnectPeer()
  # echo lndOpenChannel()
  # lndGetChannelBalance()
  # echo lndOpenChannel()
  # sleep 5000
  # lndGetChannelBalance()

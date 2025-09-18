import ./lndapi
import ./crypto/lnd
import ./shared
import ./dbcode
import ./middle
import sugar
import sequtils
import json 
import tables
import results
import options
import jsony
import times
import db_connector/db_sqlite

type
  APIPayInvoiceRequest = object
    payReq : string

    maxAmtSat = some(0.uint64)
    minAmtSatSat = some(0.uint64)

    maxAmtBtc = some(0.float64)
    minAmtSatBtc = some(0.float64)

    specificAmount = some(false)
    amp : Option[bool]
  APIOpenChannel = object
    pubKey : string 

    localFundingAmtSat = some(0.uint64)
    localFundingAmtBtc = some(0.0.float64)
    pushAmtSat = some(0.0.uint64)
    pushAmtBtc = some(0.0.float64)

    closeAddress = some("")
    private = some(false)
    memo = some("")
    targetConf = some(6)
  APIAddInvoice= object
    memo = some("")
    amtSat = some(0.uint64)
    amtBtc = some(0.float64)
    validDuration = some(0)
    isAmp = some(false)
    callback = some(newJNull())
  APICloseChannel = object
    txStr : string
    outputIndex : int
    deliveryAddress = some("")
    targetConf = some(6.uint)
    force = some(false)
  APINewDepositRequest = object
    amtBtc = some(0.float64) 
    amtSat = some(0.uint64) 
    coinType = some(BTC)
    userRowId = some(1) 
    callback = some(newJNull())
    expiryLength = some(7200.uint64)

  APINewWithdrawalRequest = object
    amtBtc = some(0.float64) 
    amtSat = some(0.uint64) 
    address : string 

    coinType = some(BTC)
    withdrawalType = some(Single)
    userRowId = some(1.uint64) 


  ApiChannelQuery = object
    mode = Both


using 
  db : DbConn
  req : JsonNode
  clients : CryptoClients



proc initApiError(a : APIException, httpCode = 500) : ApiResponse = 
  let inter =  AlbaBTCException(etype: API, timeCreated : now().toTime().toUnix(), external : a)

  result = ApiResponse(httpCode : httpCode, isError : true, error : inter)



proc convertResult[T](a : Result[T, AlbaBTCException], httpCode = 200) : ApiResponse =
  if a.isOk:
    return ApiResponse(isError: false, result : parseJson toJson a.get(), httpCode : httpCode)
  else:
    return ApiResponse(isError: true, error : a.error(), httpCode : httpCode)

proc convertResult[T](a : Option[T], error : APIException, httpCode = 200) : ApiResponse =
  if a.isSome():
    return ApiResponse(isError: false, result : parseJson toJson a.get(), httpCode : httpCode)
  else:
    return initApiError(error)


proc getAmtSat(a : Option[uint64], b : Option[float64]) : Option[uint64] =
  if a.isNone() and b.isNone():
    return 
  elif a.isSome():
    return a
  elif a.isNone() and b.isSome():
    return some ((b.get()*100_000_000.0).uint64)

proc getAmtBtc(a : Option[uint64], b : Option[float64]) : Option[float64] =
  if a.isNone() and b.isNone():
    return
  elif b.isSome():
    return b
  elif a.isSome() and b.isNone():
    return some ((float64(a.get()) / 100_000_000.0).float64)

template earlyExit[T](a: Result[T, AlbaBTCException]) : untyped =
  if a.isErr:
    return ApiResponse(isError: true, error : a.error(), httpCode : 500)
  a.get()  

template tryTo[T](a : JsonNode, b : typedesc[T]) : untyped =
  try:
    a["params"].to(b)
  except:
    return initApiError(ParamParsingError)

proc apiPayInvoice*(req, clients, db) : ApiResponse = 

  let request = req.tryTo(APIPayInvoiceRequest)

  let max = getAmtSat(request.maxAmtSat, request.maxAmtBtc)

  let min = getAmtSat(request.minAmtSatSat, request.minAmtSatBtc)

  if max.isNone():
    return initApiError(AmtRequiredButNotGiven)

  let invoiceInfo = earlyExit lndGetInvoiceInfo(request.payReq)

  let output = lndPayInvoice(request.payReq, max.get(), invoiceInfo, min.get(0), request.specificAmount.get(), request.amp.get())

  if output.isOk:
    let insert = sql"insert into LndInvoicePaid(NumSatoshi, Invoice, RHash) values (?,?,?)"  

    db.exec(insert, invoiceInfo.numSatoshis, request.payReq, invoiceInfo.paymentHash)

  return convertResult output

proc apiOpenChannel*(req, clients, db) : ApiResponse = 

  let request = req.tryTo(APIOpenChannel)

  let lclAmt = getAmtSat(request.localFundingAmtSat, request.localFundingAmtBtc)
  let pushAmt = getAmtSat(request.pushAmtSat, request.pushAmtBtc)

  if lclAmt.isNone():
    return initApiError(AmtRequiredButNotGiven)

  let output = lndOpenChannel(request.pubKey, lclAmt.get(), request.closeAddress.get(), 

  request.private.get(), request.memo.get(), pushAmt.get(0),  request.targetConf.get())

  result = convertResult output

  if output.isOk():
    let got = output.get()

    let insert = sql"""insert into LndChannelOpened(
      FundingTxId, OutputIndex, LclNumSatoshi,
      PushAmtSat, Pubkey
    ) VALUES (?, ?, ?,?,?)
    """

    db.exec(insert,  got.fundingTxStr, got.outputIndex,
      lclAmt.get(), pushAmt.get(), request.pubKey
    )

  result = convertResult output



proc apiAddInvoice(req, clients, db) : ApiResponse = 

  let request = req.tryTo(APIAddInvoice)

  let amt = getAmtSat(request.amtSat, request.amtBtc)
  if amt.isNone():
    return initApiError(AmtRequiredButNotGiven)

  let output = lndAddInvoice(request.memo.get(), amt.get(), request.validDuration.get(), request.isAmp.get())

  if output.isOk:
    let got = output.get()

    let insert = sql"insert into LndInvoiceAdd(NumSatoshi, Invoice, Rhash, CallBack) values (?,?,?, NULLIF(?, 'null'))"  

    db.exec(insert, request.amtSat, got.paymentRequest, got.rHash, $(request.callback.get()))

  result = convertResult output

proc apiCloseChannel(req, clients, db) : ApiResponse = 

  let request = req.tryTo(APICloseChannel)

  let output = lndCloseChannel(request.txStr, request.outputIndex, request.deliveryAddress.get(), request.targetConf.get(), request.force.get())

  if output.isOk:
    let channeLInfoInter = earlyExit lndListChannels()
  
    let channelInfo = channeLInfoInter.filter(x=> x.channelPoint == request.txStr)

    #TODO: MAKE ERROR

    if channelInfo.len == 0:
      return

    let chaninfo = channelInfo[0]

    let got = output.get()

    let insert = sql"""insert into LndChannelClose(

    ChannelId, FundingTxId, NumSatoshiSent,
    NumSatoshiReceived, Pubkey, Initialted) values (?,?.?,?,?,?)"""

    db.exec(insert, chaninfo.chanId, request.txStr, chaninfo.totalSatoshisSent, chaninfo.totalSatoshisReceived, chaninfo.remotePubkey, chaninfo.initiator)

  result = convertResult output

proc apiBtcNewDeposit(req, clients, db) : ApiResponse = 

  let request = req.tryTo(APINewDepositRequest)

  let amt = getAmtBtc(request.amtSat, request.amtBtc)

  if amt.isNone():
    return initApiError(AmtRequiredButNotGiven)

  if not userExists(db, request.userRowId.get()):
    return initApiError(UserDoesntExist)

  let output = createDepositRequest(db, clients,request.coinType.get(),  amt.get(), request.expiryLength.get(), request.userRowId.get(), request.callback.get())

  #TODO: make this not opaque aas hell
  result = convertResult(output, UnknownInternalError)
    

proc apiNewWithdrawalRequest(req, clients, db) : ApiResponse = 

  let request = req.tryTo(APINewWithdrawalRequest)

  let amt = getAmtBtc(request.amtSat, request.amtBtc)

  if amt.isNone():
    return initApiError(AmtRequiredButNotGiven)

  let user = getUser(db, request.userRowId.get())

  if user.isNone():
    return initApiError(UserDoesntExist)
    return


  let output = createWithdrawalRequest(db, user.get(), request.address, 
        request.coinType.get(), request.withdrawalType.get(), amt.get())

let endPoints* = {
  "lndPayInvoice" : apiPayInvoice, 
  "lndOpenChannel" : apiOpenChannel, 
  "lndAddInvoice" : apiAddInvoice,
  "lndCloseChannel" : apiCloseChannel, 
  "btcNewDeposit" : apiBtcNewDeposit, 
  "btcWithdrawalRequest" : apiNewWithdrawalRequest,
}

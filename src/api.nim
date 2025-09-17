import ./lndapi
import ./crypto/lnd
import ./shared
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
    maxAmt : uint64
    minAmt = some(0.uint64)
    specificAmount = some(false)
    amp : Option[bool]
    callback = some(newJNull())
  APIOpenChannel = object
    pubKey : string 
    localFundingAmtSat : uint64
    closeAddress = some("")
    private = some(false)
    memo = some("")
    pushSat = some(0.uint64)
    targetConf = some(6)
  APIAddInvoice= object
    memo = some("")
    amtSat = some(0.uint64)
    validDuration = some(0)
    isAmp = some(false)
    callback = some(newJNull())
  APICloseChannel = object
    txStr : string
    outputIndex : int
    deliveryAddress = some("")
    targetConf = some(6.uint)
    force = some(false)

  ApiResult = Result[string, AlbaBTCException] 

using 
  db : DbConn
  req : JsonNode

proc convertResult[T](a : Result[T, AlbaBTCException]) : ApiResult =
  if a.isOk:
    return ok a.get().toJson()
  else:
    return err a.error()

template earlyExit[T](a: Result[T, AlbaBTCException]) : T =
  if a.isErr:
    return err a.error()
  a.get()  

proc apiPayInvoice*(req, db) : ApiResult = 

  let request = req.to(APIPayInvoiceRequest)

  let invoiceInfo = earlyExit lndGetInvoiceInfo(request.payReq)

  let output = lndPayInvoice(request.payReq, request.maxAmt, invoiceInfo, request.minAmt.get(), request.specificAmount.get(), request.amp.get())

  if output.isOk:
    let insert = sql"insert into LndInvoicePaid(NumSatoshi, Invoice, RHash, callback) values (?,?,?, NULLIF(?, 'null'))"  

    db.exec(insert, invoiceInfo.numSatoshis, request.payReq, invoiceInfo.paymentHash, $(request.callback.get()))

  return convertResult output

proc apiOpenChannel*(req, db) : ApiResult = 

  let request = req.to(APIOpenChannel)

  let output = lndOpenChannel(request.pubKey, request.localFundingAmtSat, request.closeAddress.get(), 

  request.private.get(), request.memo.get(), request.pushSat.get(),  request.targetConf.get()
  )

  result = convertResult output

  if output.isOk():
    let got = output.get()

    let insert = sql"""insert into LndChannelOpened(
      FundingTxId, OutputIndex, LclNumSatoshi,
      PushAmtSat, Pubkey
    ) VALUES (?, ?, ?,?,?)
    """

    db.exec(insert,  got.fundingTxStr, got.outputIndex,

    request.localFundingAmtSat, request.pushSat.get(), request.pubKey

    )

  result = convertResult output



proc apiAddInvoice(req, db) : ApiResult = 

  let request = req.to(APIAddInvoice)

  let output = lndAddInvoice(request.memo.get(), request.amtSat.get(), request.validDuration.get(), request.isAmp.get())

  if output.isOk:
    let got = output.get()

    let insert = sql"insert into LndInvoiceAdd(NumSatoshi, Invoice, Rhash, CallBack) values (?,?,?, NULLIF(?, 'null'))"  

    db.exec(insert, request.amtSat, got.paymentRequest, got.rHash, $(request.callback.get()))

  result = convertResult output

proc apiCloseChannel(req, db) : ApiResult = 

  let request = req.to(APICloseChannel)

  let output = lndCloseChannel(request.txStr, request.outputIndex, request.deliveryAddress.get(), request.targetConf.get(), request.force.get())

  if output.isOk:
    let channeLInfo = lndListChannels().get().filter(x=> x.channelPoint == request.txStr)

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


# let x = $newJNull()
# echo x

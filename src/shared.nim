import options
import times
import NimBTC
import results
import typetraits
import libcurl
import json

type
  Exceptions*  = enum
    ErrorChangingRow = "errorUpdatingRow", BtcWithdrawalNotEnoughFunds = "notEnoughFunds", BtcFailedToCreateTx = "failedToCreateTx",
    BtcFailedToSubmitRawTx = "failedToSubmitRawTx", BtcMultipleCoinsInWithdrawal = "multipleCoinsInWithdrawal", BtcIncorrectCoinInWithdrawal = "incorrectCoinInWithdrawal", BtcAddressNotFound = "BtcAddressNotFound",

    LndFailedToGetInfo = "LndFailedToGetInfo", LndBadFundAmt = "LndBadFundAmmt"
  APIException* = enum
    JsonParsingError = "JsonParsingError"
  CoinType* = enum
    BTC = "BTC"
  CryptoClients* = object
    btcClient* : options.Option[BTCClient]
  EType = enum
    Internal, LND, Curl, API 

  AlbaBTCException* = object
    timeCreated : int64 
    case etype: EType
    of Internal:
      error : Exceptions
    of LND:
      code* : int
      message* : string
      details* : JsonNode
    of Curl:
      libcurlError* : Code
    of API:
      external* : APIException

proc albaBTCException*(error : Exceptions): AlbaBTCException =
   result.timeCreated = now().toTime().toUnix
   result.error = error

proc libCurlError*(code : Code) : AlbaBTCException =
  result.timeCreated = now().toTime().toUnix
  result = AlbaBTCException(etype : Curl, libcurlError : code)

proc lndError(code : int, message : string, details : JsonNode) : AlbaBTCException =
  result = AlbaBTCException(etype : LND, code : code, message : message, details : details)
  result.timeCreated = now().toTime().toUnix

proc tagErr*[A; T: AlbaBTCException](a : Result[A, T], b : Exceptions) : Result[A, T] = 
  ## Assumes its an err, and tags it with a specific failiure type

  var got = a.error()
  got.error = b
  return err got

  

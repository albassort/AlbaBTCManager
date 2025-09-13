import options
import times
import NimBTC
import results
import ./crypto/lndApiObjects
import typetraits

type
  Exceptions*  = enum
    ErrorChangingRow = "errorUpdatingRow", BtcWithdrawalNotEnoughFunds = "notEnoughFunds", BtcFailedToCreateTx = "failedToCreateTx",
    BtcFailedToSubmitRawTx = "failedToSubmitRawTx", BtcMultipleCoinsInWithdrawal = "multipleCoinsInWithdrawal", BtcIncorrectCoinInWithdrawal = "incorrectCoinInWithdrawal", BtcAddressNotFound = "BtcAddressNotFound",

    LndFailedToGetInfo = "LndFailedToGetInfo", LndBadFundAmt = "LndBadFundAmmt"


  
  CryptoClients* = object
    btcClient* : Option[BTCClient]

  AlbaBTCException* = object of RootObj
    timeCreated : int64 
    error : Exceptions


proc albaBTCException*(error : Exceptions): AlbaBTCException =
   result.timeCreated = now().toTime().toUnix
   result.error = error

proc tagErr*[A; T: AlbaBTCException](a : Result[A, T], b : Exceptions) : Result[A, T] = 
  ## Assumes its an err, and tags it with a specific failiure type

  var got = a.error()
  got.error = b
  return err got

  

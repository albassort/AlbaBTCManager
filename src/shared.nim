import options
import NimBTC
type
  Exceptions*  = enum
    ErrorChangingRow = "errorUpdatingRow", NotEnoughFunds = "notEnoughFunds", FailedToCreateTx = "failedToCreateTx",
    FailedToSubmitRawTx = "failedToSubmitRawTx", MultipleCoinsInWithdrawal = "multipleCoinsInWithdrawal", IncorrectCoinInWithdrawal = "incorrectCoinInWithdrawal", addresNotFound = "addresNotFound"
  CryptoClients* = object
    btcClient* : Option[BTCClient]


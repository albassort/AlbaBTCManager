import ./crypto/lnd
import ./shared
import ./crypto/lndApiObjects
import db_connector/db_sqlite
export lnd
export lndApiObjects
import ./init
import ./shared
import times

proc lndPayInvoice*(payReq : string, maxAmt : uint64,
  invoiceInfo : LndInvoiceData, minAmt : uint64 = 0, specificAmount : bool , amp = false
  ) : Result[LndPayInvoiceResult, AlbaBTCException] =
  
  ##A specific amount would be paid to an invoice without a amt set
  #
  if invoiceInfo.numSatoshis > maxAmt or minAmt > invoiceInfo.numSatoshis:
    return err albaBTCException(LndBadFundAmt)
    
  if not specificAmount:
    result = lndPayInvoiceImp(payReq, 0, amp)
  else:
    result = lndPayInvoiceImp(payReq, maxAmt, amp)

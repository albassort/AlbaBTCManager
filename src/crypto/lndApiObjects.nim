type InvoiceResult* = object
  rHash : string
  paymentRequest* : string
  addIndex* : string
  paymentAddr* : string 
type CreateChannelResult* = object
  fundingTxidBytes* : string
  fundingTxStr* : string
  outputIndex* : int
type CloseChannelResult* = object
  txid* : string
  txidStr* : string
  outputIndex* : int
  feePerVByte : string
  localCloseTx : bool
  

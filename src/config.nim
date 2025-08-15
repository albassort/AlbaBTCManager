import yaml, streams
type 
  DepositCallbacks*[T] = object 
    noChange* : T
    fundingIncreased* : T
    expired* : T
    fullyFunded* : T
  ExceptionsCallbacks*[T] = object
    errorUpdatingRow* : T
    notEnoughFunds* : T
    failedToSubmitRawTx* : T
    failedToCreateTx* : T
    multipleCoinsInWithdrawal* : T
    incorrectCoinInWithdrawal* : T
  ChannelsCallbacks*[T] = object
    channelCreated : T
    invoicedPaid : T
    channelOpenTxConfirm : T
    channelClosed : T
    channelCloseTxConfirm : T
  WithdrawalsCallbacks*[T] = object
    withdrawalCreated : T
    groupWithdrawalFulfilled : T
    singleWithdrawalCreated : T
    withdrawalTxConfirmed : T
  XMRCallbacks*[T] = object
    newBlockConfirmed : T
    newUTXOUnlocked : T
  BTCCallbacks*[T] = object
    newBlockConfirmed : T
  BTCCoreConfig* = object
    rpcIp* : string
    rpcPort* : int
    rpcUserName* : string
    rpcPassword* : string
    zmqpubhashblock* : string
  LND* = object
    macroon : string
    restPort : int
    restIp : string
    tlsPath : string
    walletPassowrd : string

  Callbacks*[T] = object
    deposits* : DepositCallbacks[T]
    exceptions* : ExceptionsCallbacks[T]
    channels : ChannelsCallbacks[T]
    withdrawals : WithdrawalsCallbacks[T] 
    btc : BTCCallbacks[T]
    xmr : XMRCallbacks[T]


  Connections* = object
    unixSocketPath* : string
    useUnix* : bool
    tcpIp* : string
    tcpPort* : int
    tcpPortRandom* : bool
    useTcp* : bool
    httpIp* : string
    httpPort* : int 
    useHttp* : bool
    connectionKey* : string
  DbConfig* = object
    sqliteDbPath* : string
    username* : string
    password* : string
    database* : string
  BTCConfig* = object
    walletName* : string
    walletPassword* : Option[string]
    depositTimeOutSeconds* : int
    depositWithdrawalPollSeconds* : int
    enableInvdividualWithdrawals* : bool
  Debug* = object
    debugPath* : string
    enableDebug* : bool
  Discord*  = object
    discordToken* : string
    discordPort* : int
    defaultChannel* : string
    useDefaultChannel* : bool
    callbacks*: Callbacks[string]
  SMTP* = object
    username* : string
    password* : string
    port* : int
    address* : string

    callbacks*: Callbacks[string]

    defaultMail* : string
    useDefaultMail* : bool
    useTLS* : bool
    useAuth* : bool
  TCP* = object
    ip* : string 
    port* : string
    broadcastOverRecievingTcp* : bool
    callbacks*: Callbacks[bool]
  UnixSocket* = object
    location* : string
    callbacks*: Callbacks[bool]
  HTTP* = object
    endpoint* : string
    auth* : string
    callbacks*: Callbacks[bool]
  NamedPipe* = object
    path* : string
    callbacks*: Callbacks[bool]
  CallBacksGroupings* = object
    discord* : Discord
    smtp* : SMTP
    tcp* : TCP
    unixSocket* : UnixSocket
    http* : HTTP
    namedPipe* : NamedPipe
  Config* = object
    connections* : Connections
    db* : DbConfig
    btcConfig* : BTCConfig
    debug* : Debug
    callbacks* : CallBacksGroupings
    btcCore* : BTCCoreConfig
    lnd* : LND
  hasCallbacksBools*[T] = concept x 
    x.callbacks is Callbacks[bool]
  hasCallbacksLocations*[T] = concept x 
    x.callbacks is Callbacks[string]


proc evaluateConfig*() : Config =
  var config: Config
  var s = newFileStream("config.yaml")
  load(s, config)
  s.close()

  doAssert(config.connections.connectionKey != "SetSomethingSecurePlease", "Please set a connection key!")

  doAssert((config.db.username != "SET ME!" and config.db.password != "SERIOUSLY"), "Please set DB protection!")

  return config
  
when isMainModule:
  let config = new Config
  var s = newFileStream("configref.yaml", fmWrite)
  Dumper().dump(config, s)
  s.close()
  echo "written"


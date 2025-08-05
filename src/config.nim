import yaml, streams
type 
  DepositBool* = object 
    noChange* : bool
    fundingIncreased* : bool
    expired* : bool
    fullyFunded* : bool
  ExceptionsBools* = object
    errorUpdatingRow* : bool
    notEnoughFunds* : bool
    failedToSubmitRawTx* : bool
    failedToCreateTx* : bool
    multipleCoinsInWithdrawal* : bool
    incorrectCoinInWithdrawal* : bool
  DepositLocations* = object 
    noChange* : string
    fundingIncreased* : string
    expired* : string
    fullyFunded* : string
  ExceptionsLocations* = object
    errorUpdatingRow* : string
    notEnoughFunds* : string
    failedToSubmitRawTx* : string
    failedToCreateTx* : string
    multipleCoinsInWithdrawal* : string
    incorrectCoinInWithdrawal* : string
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
    depositTimeOutSeconds* : int
    walletName* : string
    defaultBtcip* : string
    defaultBtcport* : int
    depositWithdrawalPollSeconds* : int
    enableInvdividualWithdrawals* : bool
  Debug* = object
    debugPath* : string
    enableDebug* : bool
  Discord*  = object
    discordToken* : string
    defaultChannel* : string
    useDefaultChannel* : bool
    deposits* : DepositLocations
    exceptions* : ExceptionsLocations
  SMTP* = object
    username* : string
    password* : string
    address* : string
    deposits* : DepositLocations
    exceptions* : ExceptionsLocations
  TCP* = object
    ip* : string 
    port* : string
    broadcastOverRecievingTcp* : bool
    deposits* : DepositBool
    exceptions* : ExceptionsBools
 
  UnixSocket* = object
    location* : string
    deposits* : DepositBool
    exceptions* : ExceptionsBools
  HTTP* = object
    endpoint* : string
    auth* : string
    deposits* : DepositBool
    exceptions* : ExceptionsBools
  NamedPipe* = object
    path* : string
    deposits* : DepositBool
    exceptions* : ExceptionsBools
  CallBacks* = object
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
    callbacks* : CallBacks


proc evaluateConfig*() : Config =
  var config: Config
  var s = newFileStream("config.yaml")
  load(s, config)
  s.close()

  doAssert(config.connections.connectionKey != "SetSomethingSecurePlease", "Please set a connection key!")

  doAssert((config.db.username != "SET ME!" and config.db.password != "SERIOUSLY"), "Please set DB protection!")

  return config


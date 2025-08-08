import yaml
import os
import tables
import ./config
import db_connector/db_sqlite
import strutils
import sets
import middle
import albaDiscord
import smtp
import posix
import strformat
import streams
import net
import nativesockets
import os

static:
  # Makes sure that the paths line up from the config to the internal enums
  let one = new ExceptionsBools
  let two = new ExceptionsLocations
  let three = new DepositLocations
  let four = new DepositBool
  for key,val in fieldPairs(one[]):
    discard parseEnum[Exceptions](key)
  for key,val in fieldPairs(two[]):
    discard parseEnum[Exceptions](key)
  for key,val in fieldPairs(three[]):
    discard parseEnum[DepositOutcome](key)
  for key,val in fieldPairs(four[]):
    discard parseEnum[DepositOutcome](key)

proc assignCallBacks(a : hasCallbacksLocations, default = "") : Table[string, string] =
  for key, callback in fieldPairs a.callbacks:
    for event, val in fieldPairs callback:
      if val == "" and default != "":
        result[$event] = default
      elif val == "" and default != "": 
        discard
      elif val != "":
        result[$event] = key

proc assignCallBacks(a : hasCallbacksBools) : Table[string, string] =
  for key, callback in fieldPairs a.callbacks:
    for event, val in fieldPairs callback:
      #well, it goes to a table of strings, and these are bools, so send is just a fill in.
      if val: result[$event] = "send"


type 
  Event = concept x
    x is DepositOutcome or x is Exceptions
  messageBackends* = enum
    SendDiscord, SendSMTP, SendTCP, SendUnixSocket, SendHTTP, SendNamedPipe
  MessageHandler* = object
    callbacksEnabled* : set[messageBackends]
    locationRoutes* : Table[messageBackends, Table[string, string]]

var discordThread : Thread[(string, cint)]
let smtpConn = newSmtp(debug=true)
var namedPipe : FIleSTream
var unixSocket = newSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP, buffered=true, inheritable=false)
var tcpSocket = newSocket()
proc initMessageManager(config : Config) : MessageHandler =
  let smtpConfig = config.callbacks.smtp
  if config.callbacks.discord.discordToken != "":
    result.callbacksEnabled.incl(SendDiscord)
    #init discord
    #TODO: add check if default channel is valid

    let defaultChannel = 
      if config.callbacks.discord.useDefaultChannel:
        config.callbacks.discord.defaultChannel
      else: 
        ""

    let discordTable = assignCallBacks(config.callbacks.discord, defaultChannel)
    initDiscord(config.callbacks.discord.discordToken, cint config.callbacks.discord.discordPort, discordThread)
    result.locationRoutes[SendDiscord] = discordTable

  if smtpConfig.address != "":
    block SMTPInit:
      try:
        smtpConn.connect(smtpConfig.address, Port smtpConfig.port)
      except CatchableError as e:
        echo "failed to connect to SMTP SERVER"
        quit 1
      try:
        smtpConn.startTls()
      except CatchableError as e:
        echo "Failed to start TLS on SMTP server"
        quit 1
      try:
        smtpConn.auth(smtpConfig.username, smtpConfig.password)
      except CatchableError as e:
        echo "Connected to SMTP server however, your authorization was invalid!"
        echo e[]
        quit 1

    let defaultAddress =
      if smtpConfig.useDefaultMail:
        smtpConfig.defaultMail
      else:
        ""

    let smtpRouting = assignCallBacks(smtpConfig, defaultAddress)
    result.locationRoutes[SendSMTP] = smtpRouting
    result.callbacksEnabled.incl(SendSMTP)

  if config.callbacks.namedPipe.path != "":
    let permissions = 0o0644.uint32
    let fd = mkfifo(cstring config.callbacks.namedPipe.path, permissions)
    doAssert(fd > 0, &"Failed to create NamedPipe at {config.callbacks.namedPipe.path}")
    namedPipe = newFileStream(config.callbacks.namedPipe.path)
    let fifoRouting = assignCallBacks(config.callbacks.namedPipe)
    result.locationRoutes[SendNamedPipe] = fifoRouting
    result.callbacksEnabled.incl(SendNamedPipe)

  if config.callbacks.unixSocket.location != "":
    try:
      connectUnix(unixSocket, config.callbacks.unixSocket.location)
    except:
      echo &"Failed to connect to unixSocket at {config.callbacks.unixSocket.location}"
      quit 1

    let unixCallbacks = assignCallBacks(config.callbacks.unixSocket)
    result.callbacksEnabled.incl(SendUnixSocket)
    result.locationRoutes[SendNamedPipe] = unixCallbacks

  if config.callbacks.tcp.ip != "" and not config.callbacks.tcp.broadcastOverRecievingTcp:
    try:
      tcpSocket.connect(config.callbacks.tcp.ip, Port(parseUint(config.callbacks.tcp.port)))
    except:
      echo &"Failed to connect to tcp at {config.callbacks.tcp.ip}:{config.callbacks.tcp.ip}"
      quit 1

    let tcpCallbacks = assignCallBacks(config.callbacks.unixSocket)
    result.callbacksEnabled.incl(SendTCP)
    result.locationRoutes[SendTCP] = tcpCallbacks
    
  if config.callbacks.http.endpoint != "":
    let httpCallbacks = assignCallBacks(config.callbacks.http)
    let testSocket = newSocket()
    var port = Port(0)
    if config.callbacks.http.endpoint.contains(":"):
      port = Port(parseUint(config.callbacks.http.endpoint.split(":")[1]))
    testSocket.connect(config.callbacks.http.endpoint, port, 500 )
    result.callbacksEnabled.incl(SendHTTP)
    result.locationRoutes[SendHTTP] = httpCallbacks

const schema = staticRead("./schema.sql")
let globalConfig* = createShared(Config, sizeof(Config))
globalConfig[] = evaluateConfig()
var db : DbConn
if not fileExists(globalConfig[].db.sqliteDbPath):

  db = open(globalConfig[].db.sqliteDbPath, globalConfig[].db.username, globalConfig[].db.password, globalConfig[].db.database)
  echo "It seems that your database does not exist yet. We will create it now."

  for table in schema.split(";"):
    if table[0] == '-': continue
    echo table
    try:
      db.exec(sql table)
    except:
      continue

  echo "please enter the new password and salt of your ADMIN user."
else:
  try:
    db = open(globalConfig[].db.sqliteDbPath, globalConfig[].db.username, globalConfig[].db.password, globalConfig[].db.database)
  except:
    echo "Failed to log into database, this is likely an issue with your authenticaiton."
    quit()

  try:
    let row = db.getRow(sql"select Username, Password, SaltIv from Users where rowid = 1 ")
    if row[0] == "":
      echo "Do stuff to ask if they want to create a database"
      quit(1)
    echo row
    if row[1] == "CHANGE" or row[2] == "ME!":
      echo "Please change the username and password of your admin user (user rowid=1)"
      quit(1)

  except Exception as e:
    echo "It seems that you haven't initiated the database, or there is some issue with it."
    echo e[]


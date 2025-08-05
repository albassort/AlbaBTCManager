import yaml
import os
import tables
import ./config
import db_connector/db_sqlite
import strutils
import sets
import middle

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

type 
  Event = concept x
    x is DepositOutcome or x is Exceptions
  messageBackends* = enum
    SendDiscord, SendSMTP, SendTCP, SendUnixSocket, SendHTTP, SendNamedPipe
  MessageHandler* = object
    callbacksEnabled* : set[messageBackends]
    locationRoutes* : Table[messageBackends, Table[string, string]]


proc initMessageManager(config : Config) : MessageHandler =
  if config.callbacks.discord.discordToken != "":
    result.callbacksEnabled.add(SendDiscord)
    #init discord
    #TODO: add check if default channel is valid
    var discordTable = initTable[string, string]()
    let defaultChannel = config.callbacks.discord.defaultChannel
    for key, val in fieldPairs config.callbacks.discord.deposits:
      if val == "" and config.callbacks.discord.useDefaultChannel:
        discordTable[key] = defaultChannel
      elif val == "" and not config.callbacks.discord.useDefaultChannel:
        discard
      else:
        discordTable[val] = key


  

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


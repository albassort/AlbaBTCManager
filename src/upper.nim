import json
import btccode
import tables
import results
import NimBTC
import taskman
import sugar
import init
import db_connector/db_sqlite
import middle
import options
import strformat

proc scheduledTasks() =
  
  let db = open(globalConfig[].db.sqliteDbPath, globalConfig[].db.username, globalConfig[].db.password, globalConfig[].db.database)

  let clients = initCryptoClients()

  let tasks = newScheduler()
  let polling = globalConfig[].btcConfig.depositWithdrawalPollSeconds


  tasks.every(polling.seconds) do ():
    echo judgeAllDeposits(clients, db)
    echo "do thing!"
  
    var outputs = initTable[string, float]()
    let newAddress = newDepositRequest(db, clients, BTC, 0.0001).get()
    outputs[newAddress] = 0.001

    echo sendBTC(clients.btcClient.get(), outputs, 6, globalConfig[].btcConfig.walletPassword)

  {.gcsafe.}:
    tasks.start()
scheduledTasks()

# nim c -r upper

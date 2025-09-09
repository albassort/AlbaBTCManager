import json
import ./crypto/btccode
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
import ./crypto/czmq
import cheapORMSqlite

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
#scheduledTasks()
proc doTxMontior() = 
  let clients = initCryptoClients()
  let url = "tcp://127.0.0.1:18014"
  for hash in listenForNewBlocks(url):
    let query = sqL"""select rowid, TxId, (BlockHeightCreated+ConfTarget), CoinType from TransactionWatch where notified is false and notFound is false"""

    for row in fastRowsTyped[(int, string, int, string)](db, query):
      let rowGot = row.get()
      let height = getBlockCount(clients.btcClient.get()).resultObject.to(int)

      let rowId = rowGot[0]
      let confBlock = rowGot[2]
      let tx = rowGot[1]

      if height >= confBlock:
        let tx = queryTx(clients.btcClient.get(), tx)
        if tx.isNone():
          db.exec(sql"update TransactionWatch set notFound = true where rowid = ?", rowId)
          continue
        else:
          echo tx
          db.exec(sql"update TransactionWatch set notified = true where rowid = ?", rowId)
          
        echo row
      
    echo hash

when isMainModule:

  let clients = initCryptoClients()

  var outputs = initTable[string, float]()
  let newAddress = newDepositRequest(db, clients, BTC, 0.0001).get()
  outputs[newAddress] = 0.001

  let tx = sendBTC(clients.btcClient.get(), outputs, 6, globalConfig[].btcConfig.walletPassword).get()

  echo tx

  let height = getBlockCount(clients.btcClient.get()).resultObject.to(int)
  echo insertTxWatch(db, tx.txId, height, 3, BTC)

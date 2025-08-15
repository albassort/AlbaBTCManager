import json
import taskman
import sugar
import init
import db_connector/db_sqlite
import middle

echo "do thing0" 
proc scheduledTasks() =
  
  let db = open(globalConfig[].db.sqliteDbPath, globalConfig[].db.username, globalConfig[].db.password, globalConfig[].db.database)

  let clients = initCryptoClients()

  let tasks = newScheduler()
  let polling = globalConfig[].btcConfig.depositWithdrawalPollSeconds
  echo "do thing1"

  tasks.every(polling.seconds) do ():
    echo judgeAllDeposits(clients, db)
    echo "do thing!"
  {.gcsafe.}:
    tasks.start()
scheduledTasks()

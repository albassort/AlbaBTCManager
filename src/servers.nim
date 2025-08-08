import net
import nativesockets
import albaHttpServer
import json
import tables
import os
import times

proc httpServer(a : (Port, ptr Channel[JsonNode])) =
  let socket = newSocket()

  let port = a[0]
  let channel = a[1]

  socket.setSockOpt(OptReusePort, true)
  socket.bindAddr(port)
  socket.listen()
  while true:
    var request = getRequest(socket)
    echo request
  echo "!"

proc recieveFromTcpConn(a : (ptr Channel[ptr Socket], ptr Channel[JsonNode])) {.thread.} =
  #inspired by TCB hehe
  var connections : Table[float, ptr Socket]
  let socketChannel = a[0]
  let targetChannel = a[1]
  var pollRate = 5
  while true:
    let request = socketChannel[].tryRecv()
    if request.dataAvailable:
      #CpuTime is used as a random, unique, nonrepeating, identifier
      connections[cpuTime()] = request.msg

    for id, socket in connections.pairs:
      var newMessage : string 
      try:
        newMessage = socket[].recvLine(timeout = 10) 
      except TimeoutError:
        continue
      except OSError:
        socket[].close()
        freeShared connections[id]
        connections.del(id)
      try:
        let json = parseJson newMessage
        targetChannel[].send(json)
      except:
        continue

    sleep pollRate


proc tcpServer(a : (Port, string, ptr Channel[JsonNode], ptr Channel[ptr Socket], bool, string)) =
  let port = a[0]
  let credentials = a[1]
  let jsonChannel = a[2]
  let socketChannel = a[3]
  let isUnix = a[4]
  let path = a[5]

  var socket = 
    if isUnix:
      newSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP, buffered=true, inheritable=false)
    else:
      newSocket()

  if isUnix:
    socket.bindUnix(path)
  else:
    socket.bindAddr(port)

  while true:

    var client = newSocket()
    var address : string
    socket.acceptAddr(client, address)
    #TODO: CHeCK CREDENTIALS 
    var shared = createShared(Socket, sizeof(Socket))
    shared[] = client
    socketChannel[].send(shared)


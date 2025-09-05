import net
import nativesockets
import albaHttpServer
import json
import tables
import os
import times
import options
import strutils
import std/epoll
import sugar
import std/endians
import middle

type BiChannel = object
  fromClient* : ptr Channel[RPCRequest]
  toClient* : ptr Channel[JsonNode]

proc sendTCP*(socket : Socket, message : string) = 
  let size = message.len

  var sizedataout = newSeq[char](size+3)

  littleendian32(addr sizedataout[0], addr size)

  copyMem(addr sizedataout[4], addr message[0], size)

  discard socket.send(addr sizedataout[0], size+4)
  
proc recvTCP*(socket : Socket, tiemout : int = 50) : string = 
  var sizeIn : array[4, byte]
  var sizeOut : array[4, byte]
  discard socket.recv(addr sizeIn[0], 4, tiemout)

  littleendian32(addr sizeOut[0], addr sizeIn[0])

  let size = cast[int32](sizeOut)

  result = socket.recv(size, tiemout)


proc spawnTestSocket() = 
  var socket = newSocket()
  socket.setSockOpt(OptReusePort, true)
  let port = Port(11522)
  socket.bindAddr(port)
  socket.listen()
  while true:
    var address = ""
    var client = newSocket()
    socket.acceptAddr(client, address)
    let recieved = recvTCP(client)
    echo recieved
    client.sendTCP("Hello!!!")

proc sendRecvTest() = 
  let socket2 = newSocket()

  let port = Port(11522)
  socket2.connect("127.0.0.1", port) 
  socket2.sendTCP("abcd")
  echo recvTCP(socket2)

# var t : Thread[void]
# createThread(t, spawnTestSocket)
# sleep 100
# sendRecvTest()
# joinThread(t)
# quit 1
#

proc readAllFromChannel[T](a : var Channel[T]) : Option[seq[T]] =
  let q = a.peek
  if q == 0 or q == -1:
    return 
  else:
    let objs = collect(for x in 0 .. q-1: a.recv)
    return some objs

proc processRequest(request : Request, authKey : string) : Option[JsonNode] = 
  if request.body.len == 0:
    request.respond(400, "Empty request body")
    return

  if "Authorization" notin request.headers or "Content-Type" notin request.headers:
    request.respond(401, "")
    return

  let contentType = request.headers["Content-Type"]

  if contentType != "application/json":
    request.respond(400, "")
    return 

  let auth = request.headers["Authorization"]
  let parts = auth.split(" ")

  if parts[0] != "Basic": 
    request.respond(401, "")
    return 

  let givenCredentials = parts[1]

  if authKey != givenCredentials:
    request.respond(401, "")
    return
    
  try:
    result = some parseJson(request.body)
  except:
    request.respond(400, "")
    return

    
##  Takes in a channel for the JSON respones and a channel with the response obj
##  Paired with its IID in order to know which response to send to who.
proc handleHttpRequest(a : (ptr Channel[JsonNode], ptr Channel[ptr Request])) =

  let toClient = a[0]
  let socketChannel = a[1]
  var pendingRequest = initTable[float, ptr Request]()
  while true:
    let newSocket = socketChannel[].tryRecv()
    if newSocket.dataAvailable:
      echo "ok we've got one!"
      let socket = newSocket.msg
      pendingRequest[cpuTime()] = socket

    let request = toClient[].tryRecv()
    if request.dataAvailable:
      echo "ok were responding"
      let jsonObj = request.msg
      let iid = jsonObj["iid"].getFloat()
      let reqeust = pendingRequest[iid]

      reqeust[].respond(200, $jsonObj)
      pendingRequest.del(iid)
      freeShared(reqeust)

    sleep 500

proc httpServer(a : (Port, string, BiChannel)) {.gcsafe, thread.} =
  let socket = newSocket()


  let port = a[0]
  let authKey = a[1]
  let channel = a[2]

  # Because we don't want to both wait for the reqeusts to have a response, as well as,poll for new requests, we make a thread for that. Where, our reqeust sit and wait for respoonses
  var t : Thread[(ptr Channel[JsonNode], ptr Channel[ptr Request])]
  let newChannel = createShared(Channel[ptr Request], sizeof(Channel[ptr Request]))

  createThread(t, handleHttpRequest, (channel.toClient, newChannel))

  newChannel[].open()

  socket.setSockOpt(OptReusePort, true)
  socket.bindAddr(port)
  socket.listen()
  while true:
    let requestTemp = getRequest(socket)
    if requestTemp.isNone:
      continue
    let request = requestTemp.get()
    let node = processRequest(request, authKey)
    if node.isNone:
      continue
    let json = node.get()
    let funct = json["func"].getStr()
    let toSend = requestTemplate(funct, "http", json)

    channel.fromClient[].send(toSend)

    let toChannel = createShared(Request, sizeof(Request))
    echo "ok you've been sent out!"

    toChannel[] = request
    newChannel[].send(toChannel)

proc manageTcpConn(a : (ptr Channel[ptr Socket], BiChannel)) {.thread.} =
  ## inspired by TCB hehe
  var connections = initTable[cint, ptr Socket]()
  #id -> cint -> connections -> socket
  var pendingReplies = initTable[float, cint]()
  let socketChannel = a[0]
  let targetChannel = a[1]
  var pollRate = 5

  const maxEpollEvents = 64
  let epoll = epoll_create(maxEpollEvents)
  let epollData = newSeq[EpollEvent](64)
  let eventHandl = addr epollData[0]
  
  while true:
    let request = socketChannel[].tryRecv()
    if request.dataAvailable:
      #CpuTime is used as a random, unique, nonrepeating, identifier
      let newSocket = request.msg

      let sfd = getFd(newSocket[])
      var eEvent : EpollEvent
      eEvent.events = EPOLLIN      
      eEvent.data.fd = cint sfd

      # register the socket's fd to be in the epoll so we can efficiently 
      # check which ones have data!
      
      let eresult = epoll_ctl(epoll, EPOLL_CTL_ADD, sfd, addr eEvent)

      connections[cint sfd] = newSocket

    # we wait for 50 ms 
    let totalRequests = epoll_wait(epoll, eventHandl, maxEpollEvents, 50)
    # if any onf the fd have any data on them
    if totalRequests != 0:
      for x in 0 .. totalRequests-1:
        # epollData should become filled with the fds with data on them
        let sfd = epollData[x].data.fd
        let socket = connections[sfd]
        var newMessage : string 
        try:
          newMessage = socket[].recvTCP(10) 
        # Encase for whatever reason theres no data
        except TimeoutError:
          echo "!"
          continue
        # If the socket cant be reached we need to close and free it
        except OSError:
          try: socket[].close()
          except: discard
          freeShared connections[sfd]
          let eresult = epoll_ctl(epoll, EPOLL_CTL_DEL, sfd, nil)

        try:
          # the iid -- internal id --- is needed to figure out which channel to send the response to
          var json = parseJson newMessage
          let funct = json["func"].getStr()
          let toSend = requestTemplate(funct, "http", json)

          targetChannel.fromClient[].send(toSend)

          pendingReplies[toSend.iid] = sfd
        except:
          continue


    let messages = readAllFromChannel targetChannel.toClient[]
    if messages.isNone(): continue
    for result in messages.get():
      let replyId = result["iid"].getFloat()
      if replyId notin pendingReplies:
        continue
      let sfd = pendingReplies[replyId]
      if sfd notin connections: 
        continue 
      let socket = connections[sfd]
      pendingReplies.del(replyId)
      try:
        socket[].sendTCP($result)
      except:
        try: socket[].close()
        except: discard
        freeShared socket
        connections.del(sfd)
        let eresult = epoll_ctl(epoll, EPOLL_CTL_DEL, sfd, nil)

proc tcpServer(a : (Port, string, ptr Channel[ptr Socket], bool, string)) =
  let port = a[0]
  let credentials = a[1]
  let socketChannel = a[2]
  let isUnix = a[3]
  let path = a[4]

  var socket = 
    if isUnix:
      newSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP, buffered=true, inheritable=false)
    else:
      newSocket()

  if isUnix:
    socket.bindUnix(path)
  else:
    echo "bindingPort"
    echo port
    socket.bindAddr(port)

  socket.listen()
  while true:

    var client = newSocket()
    var address : string
    socket.acceptAddr(client, address)

    #TODO: Check CREDENTIALS 
    #
    var shared = createShared(Socket, sizeof(Socket))
    shared[] = client
    socketChannel[].send(shared)


proc httpTest() = 
  let fromClient = createShared(Channel[RPCRequest], sizeof(Channel[RPCRequest]))
  let toClient = createShared(Channel[JsonNode], sizeof(Channel[JsonNode]))
  fromClient[].open()
  toClient[].open()
  let biChannel = BiChannel(fromClient : fromClient, toClient : toClient)

  let port = Port(5080)
  var t : Thread[(Port, string, BiChannel)]
  createThread(t, httpServer, (port, "!", biChannel))
  while true:
    let data = biChannel.fromClient[].tryRecv
    if data.dataAvailable:
      echo "ok got a request from a client sending my response!"
      let request = data.msg
      let response = newJObject()
      response["iid"] = newJFloat request.iid
      response["big step"] = newJBool true
      biChannel.toClient[].send(response)
    sleep 500
  
proc tcpTest() = 
  let socketChannel = createShared(Channel[ptr Socket], sizeof(Channel[ptr Socket]))
  let fromClient = createShared(Channel[RPCRequest], sizeof(Channel[RPCRequest]))
  let toClient = createShared(Channel[JsonNode], sizeof(Channel[JsonNode]))

  socketChannel[].open()
  fromClient[].open()
  toClient[].open()

  let biChannel = BiChannel(fromClient : fromClient, toClient : toClient)

  let port = Port(5192)
  let password = "!"
  let isUnix = false
  let path = ""
    
  var tcpThread : Thread[(Port, string, ptr Channel[ptr Socket], bool, string)]
  var manageTcpConns : Thread[(ptr Channel[ptr Socket], BiChannel)]
  
  createThread(tcpThread, tcpServer, (port, password, socketChannel, false, "") )
  createThread(manageTcpConns, manageTcpConn, (socketChannel, biChannel))
  
  sleep 100
  var testObj = newJObject()
  testObj["test"] = newJInt 0
  let testSocket = newSocket()
  testSocket.connect("127.0.0.1", port) 
  testSocket.sendTCP($testObj)
  sleep 100
  let obj = fromClient[].tryRecv.msg
  toClient[].send(newJObject())
  echo testSocket.recvTCP()

tcpTest()

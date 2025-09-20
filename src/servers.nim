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
import ./shared
import jsony
import ./api

type BiChannel = object
  fromClient* : ptr Channel[RPCRequest]
  toClient* : ptr Channel[RPCResponse]

proc newRPCRequest(a : Sources, id : float, body : JsonNode) : RPCRequest =
  result.source = a 
  result.id = id
  result.body = body
  result.timeRecieved = now().toTime().toUnix()

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
    let received = recvTCP(client)
    echo received
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

  # if "Authorization" notin request.headers or "Content-Type" notin request.headers:
  #   request.respond(401, "")
  #   return
  #
  # let contentType = request.headers["Content-Type"]
  #
  # if contentType != "application/json":
  #   request.respond(400, "")
  #   return 
  #
  # let auth = request.headers["Authorization"]
  # let parts = auth.split(" ")
  #
  # if parts[0] != "Basic": 
  #   request.respond(401, "")
  #   return 
  #
  # let givenCredentials = parts[1]
  #
  # if authKey != givenCredentials:
  #   request.respond(401, "")
  #   return
  #
  try:
    result = some parseJson(request.body)
  except:
    request.respond(400, "")
    return

    
##  Takes in a channel for the JSON respones and a channel with the response obj
##  Paired with its IID in order to know which response to send to who.
proc handleHttpRequest(a : (ptr Channel[RPCResponse], ptr Channel[(ptr Request, float64)])) =

  let toClient = a[0]
  let socketChannel = a[1]
  var pendingRequest = initTable[float, ptr Request]()
  while true:
    let newSocket = socketChannel[].tryRecv()
    if newSocket.dataAvailable:
      echo "ok we've got one!"
      let msg = newSocket.msg
      let socket = msg[0]
      let id = msg[1]
      pendingRequest[id] = socket

    let request = toClient[].tryRecv()
    if request.dataAvailable:
      echo "ok were responding"
      let response = request.msg
      let reqeust = pendingRequest[response.id]
      reqeust[].respond(response.response.httpCode, toJson response.response)

      pendingRequest.del(response.id)
      freeShared(reqeust)

    sleep 50

proc httpServer(a : (Port, string, BiChannel)) {.gcsafe, thread.} =
  let socket = newSocket()

  let port = a[0]
  let authKey = a[1]
  let channel = a[2]

  # Because we don't want to both wait for the reqeusts to have a response, as well as,poll for new requests, we make a thread for that. Where, our reqeust sit and wait for respoonses
  var t : Thread[(ptr Channel[RPCResponse], ptr Channel[(ptr Request,float64)])]
  let newChannel = createShared(Channel[(ptr Request,  float64)], sizeof(Channel[( ptr Request, float64)]))

  createThread(t, handleHttpRequest, (channel.toClient, newChannel))

  newChannel[].open()

  socket.setSockOpt(OptReusePort, true)
  socket.bindAddr(port)
  socket.listen()
  while true:
    echo "req"
    let requestTemp = getRequest(socket)
    echo "aaa"
    if requestTemp.isNone:
      continue
    let request = requestTemp.get()
    let node = processRequest(request, authKey)
    echo "hello"
    if node.isNone:
      #TODO: RESPOND
      continue

    echo "gust"

    # Assembles the request and sends it out
    let id = cpuTime()
    let json = node.get()

    let toSend = newRPCRequest(http, id, json)
    channel.fromClient[].send(toSend)

    # Sneds out the Request to handle closing on a different thread
    let toChannel = createShared(Request, sizeof(Request))
    toChannel[] = request
    newChannel[].send((toChannel, id))

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
    ##HANDELS TCB CONNECTIONS. Closes after reply is sent from the processor.
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
          let iid = cpuTime()
          var json = parseJson newMessage
          let toSend = newRPCRequest(tcp, iid, json)

          targetChannel.fromClient[].send(toSend)

          pendingReplies[iid] = sfd
        except:
          continue


    let messages = readAllFromChannel targetChannel.toClient[]
    if messages.isNone(): continue
    for result in messages.get():
      let replyId = result.id
      if replyId notin pendingReplies:
        continue
      let sfd = pendingReplies[replyId]
      if sfd notin connections: 
        continue 
      let socket = connections[sfd]
      pendingReplies.del(replyId)
      try:
        socket[].sendTCP(toJson (result.response))
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

    var shared = createShared(Socket, sizeof(Socket))
    shared[] = client
    socketChannel[].send(shared)


proc httpTest() = 
  let fromClient = createShared(Channel[RPCRequest], sizeof(Channel[RPCRequest]))
  let toClientHttp = createShared(Channel[RPCResponse], sizeof(Channel[RPCResponse]))
  fromClient[].open()
  toClientHttp[].open()
  let biChannel = BiChannel(fromClient : fromClient, toClient : toClientHttp)

  let port = Port(5080)
  var t : Thread[(Port, string, BiChannel)]
  createThread(t, httpServer, (port, "!", biChannel))

  while true:
    let data = biChannel.fromClient[].tryRecv
    if data.dataAvailable:
      echo "ok got a request from a client sending my response!"
      let request = data.msg

      let response = AlbaBTCException(etype: API, timeCreated : now().toTime().toUnix(), external : JsonParsingError)

      let output = ApiResponse(isError: true, error : response, httpCode : 200)

      let toOutput = makeRPCResponse(output, request.id)

      biChannel.toClient[].send(toOutput)
    sleep 50

proc tcpTest()= 
  let socketChannel = createShared(Channel[ptr Socket], sizeof(Channel[ptr Socket]))
  let fromClient = createShared(Channel[RPCRequest], sizeof(Channel[RPCRequest]))
  let toClient = createShared(Channel[RPcResponse], sizeof(Channel[RPCResponse]))

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

  let response = AlbaBTCException(etype: API, timeCreated : now().toTime().toUnix(), external : JsonParsingError)

  let output = ApiResponse(isError: true, error : response, httpCode : 200)

  let obj = fromClient[].tryRecv.msg
  let toOutput = makeRPCResponse(output, obj.id)

  toClient[].send(toOutput)

  echo testSocket.recvTCP()

proc runApi() = 
  discard ""

  # The architecture of a TCP and HTTP handler is as follows. 
  # 1. A connection is received, each listener is on its own thread.
  # 2. Its FD is copied into an object on shared memory, and sent to a function designed for holding the connection, and sending a response out when recieved
  # 3. All connections feed into a main handler, which, which is this function, and is on the main handle. 

  # This thread gets all the RCP reqeusts from all channels. All requests leads here.
  let fromClient = createShared(Channel[RPCRequest], sizeof(Channel[RPCRequest]))

  let password = "!"
  let httpPort = Port(5080)
  var httpThread : Thread[(Port, string, BiChannel)]
  
  # This thread directs to HTTP handler channel. The response is sent to the desired client, and, the connection is closed, the socket is dealloced
  let toClientHttp = createShared(Channel[RPCResponse], sizeof(Channel[RPCResponse]))

  fromClient[].open()
  toClientHttp[].open()

  # 
  let httpBiChannel = BiChannel(fromClient : fromClient, toClient : toClientHttp)

  createThread(httpThread, httpServer, (httpPort, password, httpBiChannel))

  sleep 1000


  # Inits TCP clients

  # This channel holds TCP sockets and handles the responses. We handle the channel, so we can support multiple TCP channels. Because, once established, TCP channels are mostly function agnostic.
  let socketChannel = createShared(Channel[ptr Socket], sizeof(Channel[ptr Socket]))

  # This connects to the TCP manager. All messages are sent to where the sockets are stored NOT to where the TCP connections are handled.
  let toClientTcp = createShared(Channel[RPCResponse], sizeof(Channel[RPCResponse]))

  let tcpBiChannel = BiChannel(fromClient : fromClient, toClient : toClientTcp)


  let tcpPort = Port(5192)
  let isUnix = false
  let path = ""

  var tcpThread : Thread[(Port, string, ptr Channel[ptr Socket], bool, string)]
  var manageTcpConns : Thread[(ptr Channel[ptr Socket], BiChannel)]
  createThread(tcpThread, tcpServer, (tcpPort, password, socketChannel, isUnix, path) )

  # This thread manages all the open TCP channels. Messages are sent to them, and they are closed.
  createThread(manageTcpConns, manageTcpConn, (socketChannel, tcpBiChannel))

  sleep 1000

  echo "API running!"

  while true:
    let request = fromClient[].tryRecv()
    let rpcRequest = 
      if request.dataAvailable:
        request.msg
      else:
        sleep 50
        continue 

    let param = rpcRequest.body["func"].getStr()
    if param notin endPoints: 
      #TODO: send rpc not found
      continue

    let rpcCall = endPoints[param]
    echo param
    
runApi()
# tcpTest()
# httpTest()

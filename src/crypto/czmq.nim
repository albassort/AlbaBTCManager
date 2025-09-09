{.passC: "-I/usr/include".}
{.passL: "-lczmq".}
{.compile: "./gethash.c".}

type zsock_t = distinct pointer
type zframe_t = distinct pointer

proc zsock_new_sub(a :cstring, b : cstring) : zsock_t {.importc: "zsock_new_sub", header: "<czmq.h>".}
proc zframe_recv(a : zsock_t): zframe_t {.importc: "zframe_recv", header: "<czmq.h>".} 
## output should be 64 bytes
proc get_hash_hex(a : zframe_t, output : cstring): bool {.importc: "get_hash_hex", header: "<czmq.h>".} 


iterator listenForNewBlocks*(url : string) : string =

  let sub = zsock_new_sub(url, "hashblock")
  while true:
    let zframe = zframe_recv(sub)
    if cast[int64](zframe) == 0:
      break
    let s: string = newString(64)
    let cs: cstring = cstring(s)
    if not get_hash_hex(zframe, cs): continue
    yield $cs

when isMainModule:
  while true:

    let sub = zsock_new_sub("", "hashblock")
    let zframe = zframe_recv(sub)
    if cast[int64](zframe) == 0:
      break
    let s: string = newString(64)
    let cs: cstring = cstring(s)
    if not get_hash_hex(zframe, cs): continue
    echo cs

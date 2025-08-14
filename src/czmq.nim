{.passl: "-lczmq".}
{.compile: "./czmq.c".}


type zsock_t {.importc: "zsock_t"} = distinct pointer
type zframe_t {.importc: "zframe_t"} = distinct pointer
proc zsock_new_sub(a :cstring, b : cstring) : zsock_t {.importc: "zsock_new_sub".}
proc zframe_recv(a : zsock_t): zframe_t {.importc: "zframe_recv".} 
## output should be 64 bytes
proc get_hash_hex(a : zframe_t, output : cstring): bool {.importc: "get_hash_hex".} 

let sub = zsock_new_sub("tcp://127.0.0.1:18014", "hashblock")
while true:
  let zframe = zframe_recv(sub)
  if cast[int64](zframe) == 0:
    break
  let s: string = newString(64)
  let cs: cstring = cstring(s)
  if not get_hash_hex(zframe, cs): continue
  echo cs

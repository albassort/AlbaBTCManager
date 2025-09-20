# Because of the lack of stability in the NIM smtp library, libESMTP is used in its stead.
import libcurl
import tables
import strformat

{.passC: "-I/usr/include".}
{.passL: "-lcurl".}
{.compile: "./curlwrapper.c".}

proc send_email_out(url, fromEmail : cstring, body : ptr cstring, recipients: Pslist, username, password : cstring ) : Code {.importc: "send_email_out", header: "<curl/curl.h>"} 

proc sendEmail*(url, fromEmail : string, recipients : seq[string], body : string, username, password : string, metaData : TableRef[string, string] = nil) = 
  var recps : Pslist
  for x in recipients:
    recps = slist_append(recps, &"<{x}>")

  var trueMap : string

  if (metaData != nil):
    for key,val in metaData.pairs:
      let meta = &"{key}: {val}\r\n"
      trueMap.add(meta)
    trueMap.add("\r\n")

  trueMap.add(body)

  let cstringy = cstring trueMap

  echo send_email_out(url, fromEmail, addr cstringy, recps, username, password)

let email = "carolinemarceano@albassort.com"
sendEmail("smtp://heracles.mxrouting.net", email, @[email], "hello, world", email, "n")

#include <stdio.h>
#include <string.h>
#include <curl/curl.h>
struct upload_status {
  char** body;
  size_t bytes_read;
};

static size_t payload_source(char *ptr, size_t size, size_t nmemb, void *userp)
{
  printf("entering\n");
  struct upload_status *upload_ctx = (struct upload_status *)userp;
  const char *data;
  size_t room = size * nmemb;

  if((size == 0) || (nmemb = 0) || (room) < 1) {

    printf("size = %ld, nmemb = %ld, room = %ld", size, nmemb, room);
    return 0;
  }

  data = upload_ctx->body[upload_ctx->bytes_read];

  if(data) {
    size_t len = strlen(data);

    printf("copying %ld. string = %s; string length = %ld", len, data, len);
    if(room < len)
      len = room;
    memcpy(ptr, data, len);
    upload_ctx->bytes_read += len;

    return len;
  }

  printf("exit 2\n");
  return 0;
}

int send_email_out(char* url, char* from_addr, char** body, struct curl_slist* recipients, char* username, char* password)
{
  CURL *curl;
  CURLcode res = CURLE_OK;

  struct upload_status upload_ctx = { .body = body, .bytes_read = 0 };

  curl = curl_easy_init();

  if (!curl){
    return 0;
  }
  /* This is the URL for your mailserver */

  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_MAIL_FROM, from_addr);
  curl_easy_setopt(curl, CURLOPT_MAIL_RCPT, recipients);

  /* We are using a callback function to specify the payload (the headers and
   * body of the message). You could just use the CURLOPT_READDATA option to
   * specify a FILE pointer to read from. */
  curl_easy_setopt(curl, CURLOPT_READFUNCTION, payload_source);
  curl_easy_setopt(curl, CURLOPT_READDATA, &upload_ctx);
  curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);

  curl_easy_setopt(curl, CURLOPT_USERNAME, username);
  curl_easy_setopt(curl, CURLOPT_PASSWORD, password);

  res = curl_easy_perform(curl);

  /* Check for errors */
  if(res != CURLE_OK)

  curl_slist_free_all(recipients);
  curl_easy_cleanup(curl);


  return (int)res;
}

//int send_email_out(char* url, char* from_addr, char** body, struct curl_slist* recipients, char* username, char* password)

static char* email = "carolinemarceano@albassort.com";
static char* reciept = "<carolinemarceano@albassort.com>";

// int main(){
//
//   struct curl_slist *recipients = NULL;
//   recipients = curl_slist_append(recipients, reciept);
//
//   char* body =   "Date: Mon, 29 Nov 2010 21:54:29 +1100\r\n"
//   "To: " TO_MAIL "\r\n"
//   "From: " FROM_MAIL "\r\n"
//   "Cc: " CC_MAIL "\r\n"
//   "Message-ID: <dcd7cb36-11db-487a-9f3a-e652a9458efd@"
//   "rfcpedant.example.org>\r\n"
//   "Subject: SMTP example message\r\n"
//   "\r\n" /* empty line to divide headers from body, see RFC 5322 */
//   "The body of the message starts here.\r\n"
//   "\r\n"
//   "It could be a lot of lines, could be MIME encoded, whatever.\r\n"
//   "Check RFC 5322.\r\n";
//
//   send_email_out("smtp://heracles.mxrouting.net", email, &body, recipients, email, "");
// }

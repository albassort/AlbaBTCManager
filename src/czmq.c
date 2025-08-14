
#include <czmq.h>
#include <stdio.h>

bool get_hash_hex(zframe_t *frame, unsigned char *result) {

  unsigned char *hash_bytes = zframe_data(frame);

  size_t hash_size = zframe_size(frame); //

  if (hash_size != 32) {
    return false;
  }

  int i = 0;
  int place = 0;
  for (i = 0; i != hash_size; i++) {
    unsigned char c = hash_bytes[i];
    unsigned char *strPlace = &result[place];
    sprintf(strPlace, "%02x", c);
    place += 2;
  }
  return true;
};

/*
 * selftest.c — assert-based checks for the network-free parts of the core:
 * base64, UTF-8 classification, password hashing and the photo resize.
 * Run with `make test`. Anything that needs a live server isn't covered.
 */
#undef NDEBUG
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

static void test_base64(void) {
  const char *plain = "hello!";
  for (size_t n = 0; n <= strlen(plain); ++n) {
    char *enc = ls_b64_encode((const uint8_t *)plain, n);
    size_t len = 0;
    uint8_t *dec = ls_b64_decode(enc, &len);
    assert(len == n && memcmp(dec, plain, n) == 0);
    free(enc);
    free(dec);
  }
  size_t len = 0;
  uint8_t *dec = ls_b64_decode("aGVs\nbG8=", &len); /* whitespace skipped */
  assert(len == 5 && memcmp(dec, "hello", 5) == 0);
  free(dec);
  dec = ls_b64_decode("not*base64", &len); /* malformed → empty */
  assert(len == 0);
  free(dec);
}

static void test_utf8(void) {
  assert(ls_utf8_valid((const uint8_t *)"caf\xC3\xA9", 5));
  assert(!ls_utf8_valid((const uint8_t *)"\xC0\x80", 2));     /* overlong */
  assert(!ls_utf8_valid((const uint8_t *)"\xED\xA0\x80", 3)); /* surrogate */
  assert(!ls_utf8_valid((const uint8_t *)"\xC3", 1));         /* truncated */
}

static void expect_hash(LSPasswordScheme scheme, const char *prefix) {
  char *out = NULL;
  LSError err = {0};
  int rc = ls_hash_password("secret", scheme, &out, &err);
  if (rc != LS_OK || strncmp(out, prefix, strlen(prefix)) != 0) {
    fprintf(stderr, "scheme %d: rc=%d out=%s reason=%s\n", scheme, rc,
            out ? out : "(null)", err.reason ? err.reason : "");
    abort();
  }
  ls_string_free(out);
}

static void test_hashes(void) {
  expect_hash(LS_PBKDF2_SHA512, "{PBKDF2-SHA512}100000$");
  expect_hash(LS_MD5, "{MD5}Xr4ilOzQ4PCOq3aQ0qbuaQ==");
  expect_hash(LS_SHA1, "{SHA}5en6G6MezRroT3XKqkdPOmY/BfQ=");
  expect_hash(LS_SMD5, "{SMD5}");
  expect_hash(LS_SSHA, "{SSHA}");
  expect_hash(LS_UNIX_CRYPT, "{CRYPT}");
  expect_hash(LS_MD5_CRYPT, "{CRYPT}$1$");
  expect_hash(LS_SHA256_CRYPT, "{CRYPT}$5$");
  expect_hash(LS_SHA512_CRYPT, "{CRYPT}$6$");
}

/* RGB of pixel (x, y), y counted from the top, of a base64 JPEG. */
static void pixel_at(const char *b64, size_t x, size_t y, uint8_t rgb[3]) {
  size_t len = 0;
  uint8_t *bytes = ls_b64_decode(b64, &len);
  CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)len);
  CGImageSourceRef src = CGImageSourceCreateWithData(data, NULL);
  CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
  assert(img && CGImageGetWidth(img) == 300 && CGImageGetHeight(img) == 300);

  uint8_t *buf = calloc(300 * 300, 4);
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(buf, 300, 300, 8, 300 * 4, space,
                                           kCGImageAlphaNoneSkipLast);
  CGContextDrawImage(ctx, CGRectMake(0, 0, 300, 300), img);
  memcpy(rgb, buf + ((y * 300) + x) * 4, 3); /* row 0 is the top row */

  CGContextRelease(ctx);
  CGColorSpaceRelease(space);
  free(buf);
  CGImageRelease(img);
  CFRelease(src);
  CFRelease(data);
  free(bytes);
}

/* A 200x100 JPEG, left half red and right half blue, tagged EXIF
 * orientation 6 (rotate 90° clockwise): it displays as 100x200 with red on
 * top. The resized square must follow the displayed orientation. */
static void test_photo_orientation(const char *dir) {
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(NULL, 200, 100, 8, 0, space,
                                           kCGImageAlphaNoneSkipLast);
  CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
  CGContextFillRect(ctx, CGRectMake(0, 0, 100, 100));
  CGContextSetRGBFillColor(ctx, 0, 0, 1, 1);
  CGContextFillRect(ctx, CGRectMake(100, 0, 100, 100));
  CGImageRef img = CGBitmapContextCreateImage(ctx);

  char path[1024];
  snprintf(path, sizeof path, "%s/orientation6.jpg", dir);
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
  CGImageDestinationRef dst =
      CGImageDestinationCreateWithURL(url, CFSTR("public.jpeg"), 1, NULL);
  int orientation = 6;
  CFNumberRef on = CFNumberCreate(NULL, kCFNumberIntType, &orientation);
  const void *keys[] = {kCGImagePropertyOrientation};
  const void *vals[] = {on};
  CFDictionaryRef props =
      CFDictionaryCreate(NULL, keys, vals, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  CGImageDestinationAddImage(dst, img, props);
  assert(CGImageDestinationFinalize(dst));
  CFRelease(props);
  CFRelease(on);
  CFRelease(dst);
  CFRelease(url);
  CGImageRelease(img);
  CGContextRelease(ctx);
  CGColorSpaceRelease(space);

  char *out = NULL;
  LSError err = {0};
  assert(ls_resize_photo_to_base64(path, &out, &err) == LS_OK);
  uint8_t top_right[3];
  uint8_t bottom_left[3];
  pixel_at(out, 250, 30, top_right);
  pixel_at(out, 50, 270, bottom_left);
  assert(top_right[0] > 150 && top_right[2] < 100);     /* red on top */
  assert(bottom_left[2] > 150 && bottom_left[0] < 100); /* blue below */
  ls_string_free(out);
  remove(path);
}

int main(int argc, char **argv) {
  test_base64();
  test_utf8();
  test_hashes();
  test_photo_orientation(argc > 1 ? argv[1] : "/tmp");
  puts("selftest: ok");
  return 0;
}

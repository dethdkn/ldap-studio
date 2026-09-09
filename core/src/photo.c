/*
 * photo.c — ls_resize_photo_to_base64.
 *
 * Same shape as the old Rust photo.rs: read the image at `path`,
 * center-crop it to a square so the 300x300 result is never distorted,
 * re-encode as JPEG, return base64 ready to store as a binary attribute.
 *
 * Uses ImageIO + CoreGraphics. `kCGInterpolationHigh` stands in for the
 * Rust `image` crate's Lanczos3 filter — the encoded bytes differ, the
 * visual quality does not.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

#define PHOTO_SIZE 300
#define JPEG_QUALITY 0.85

int ls_resize_photo_to_base64(const char *path, char **out, LSError *err) {
  if (!path || !out)
    return ls_fail(err, LS_DECODE_FAILED, NULL, 0, "missing argument");
  *out = NULL;

  int rc = LS_OK;
  CFURLRef url = NULL;
  CGImageSourceRef src = NULL;
  CGImageRef img = NULL;
  CGImageRef square = NULL;
  CGImageRef scaled = NULL;
  CGColorSpaceRef space = NULL;
  CGContextRef ctx = NULL;
  CFMutableDataRef jpeg = NULL;
  CGImageDestinationRef dst = NULL;

  url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path,
                                                (CFIndex)strlen(path), false);
  if (!url) {
    rc = ls_fail(err, LS_DECODE_FAILED, NULL, 0, "bad path");
    goto done;
  }

  src = CGImageSourceCreateWithURL(url, NULL);
  if (!src) {
    rc = ls_fail(err, LS_DECODE_FAILED, NULL, 0, "could not open the image");
    goto done;
  }

  img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
  if (!img) {
    rc = ls_fail(err, LS_DECODE_FAILED, NULL, 0, "could not decode the image");
    goto done;
  }

  size_t w = CGImageGetWidth(img);
  size_t h = CGImageGetHeight(img);
  if (w == 0 || h == 0) {
    rc = ls_fail(err, LS_DECODE_FAILED, NULL, 0, "image has zero size");
    goto done;
  }

  size_t side = w < h ? w : h;
  size_t crop_x = (w - side) / 2; /* whole-pixel offsets, on purpose */
  size_t crop_y = (h - side) / 2;
  CGRect crop = CGRectMake((CGFloat)crop_x, (CGFloat)crop_y, (CGFloat)side,
                           (CGFloat)side);
  square = CGImageCreateWithImageInRect(img, crop);
  if (!square) {
    rc = ls_fail(err, LS_ENCODE_FAILED, NULL, 0, "could not crop the image");
    goto done;
  }

  space = CGColorSpaceCreateDeviceRGB();
  ctx = CGBitmapContextCreate(NULL, PHOTO_SIZE, PHOTO_SIZE, 8, 0, space,
                              kCGImageAlphaNoneSkipLast);
  if (!ctx) {
    rc = ls_fail(err, LS_ENCODE_FAILED, NULL, 0,
                 "could not allocate the canvas");
    goto done;
  }

  CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
  CGContextDrawImage(ctx, CGRectMake(0, 0, PHOTO_SIZE, PHOTO_SIZE), square);
  scaled = CGBitmapContextCreateImage(ctx);
  if (!scaled) {
    rc = ls_fail(err, LS_ENCODE_FAILED, NULL, 0,
                 "could not rasterize the resized image");
    goto done;
  }

  jpeg = CFDataCreateMutable(NULL, 0);
  dst = CGImageDestinationCreateWithData(jpeg, CFSTR("public.jpeg"), 1, NULL);
  if (!dst) {
    rc = ls_fail(err, LS_ENCODE_FAILED, NULL, 0,
                 "could not create the JPEG encoder");
    goto done;
  }

  {
    const void *keys[] = {kCGImageDestinationLossyCompressionQuality};
    CGFloat q = JPEG_QUALITY;
    CFNumberRef qn = CFNumberCreate(NULL, kCFNumberCGFloatType, &q);
    const void *vals[] = {qn};
    CFDictionaryRef props =
        CFDictionaryCreate(NULL, keys, vals, 1, &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);
    CGImageDestinationAddImage(dst, scaled, props);
    CFRelease(props);
    CFRelease(qn);
  }

  if (!CGImageDestinationFinalize(dst)) {
    rc = ls_fail(err, LS_ENCODE_FAILED, NULL, 0, "JPEG encoding failed");
    goto done;
  }

  *out = ls_b64_encode((const uint8_t *)CFDataGetBytePtr(jpeg),
                       (size_t)CFDataGetLength(jpeg));

done:
  if (dst) CFRelease(dst);
  if (jpeg) CFRelease(jpeg);
  if (ctx) CGContextRelease(ctx);
  if (space) CGColorSpaceRelease(space);
  if (scaled) CGImageRelease(scaled);
  if (square) CGImageRelease(square);
  if (img) CGImageRelease(img);
  if (src) CFRelease(src);
  if (url) CFRelease(url);
  return rc;
}

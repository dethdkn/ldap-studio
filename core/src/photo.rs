use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use image::imageops::FilterType;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum PhotoError {
    #[error("Couldn't read or decode the image: {reason}")]
    DecodeFailed { reason: String },
    #[error("Couldn't encode the resized image: {reason}")]
    EncodeFailed { reason: String },
}

const PHOTO_SIZE: u32 = 300;

/// Reads the image at `path`, center-crops it to a square — so resizing to
/// exactly 300x300 never distorts it, the longer dimension's excess is cut
/// instead of being squeezed — and returns the JPEG-encoded result as
/// base64, ready to store directly as a binary attribute value.
#[uniffi::export]
pub fn resize_photo_to_base64(path: String) -> Result<String, PhotoError> {
    let img = image::open(&path).map_err(|e| PhotoError::DecodeFailed {
        reason: e.to_string(),
    })?;

    let (width, height) = (img.width(), img.height());
    let side = width.min(height);
    let x = (width - side) / 2;
    let y = (height - side) / 2;
    let square = img.crop_imm(x, y, side, side);
    let resized = square.resize_exact(PHOTO_SIZE, PHOTO_SIZE, FilterType::Lanczos3);

    let mut bytes: Vec<u8> = Vec::new();
    resized
        .to_rgb8()
        .write_to(&mut std::io::Cursor::new(&mut bytes), image::ImageFormat::Jpeg)
        .map_err(|e| PhotoError::EncodeFailed {
            reason: e.to_string(),
        })?;

    Ok(BASE64.encode(bytes))
}

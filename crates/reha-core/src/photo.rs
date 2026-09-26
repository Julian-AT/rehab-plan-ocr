//! Decode into the upright original frame before any user page correction.
use crate::{Error, Result};
use image::{DynamicImage, ImageFormat, ImageReader};
use std::io::Cursor;

pub(crate) struct DecodedPhoto {
    pub image: DynamicImage,
    pub source_width: u32,
    pub source_height: u32,
    pub orientation: u32,
    pub source_is_png: bool,
}

pub(crate) fn check_dimensions(width: u64, height: u64) -> Result<()> {
    if width == 0 || height == 0 || width.checked_mul(height).is_none_or(|n| n > 50_000_000) {
        return Err(Error::Invalid(
            "Bildabmessungen nicht unterstützt (maximal 50 Megapixel).".into(),
        ));
    }
    Ok(())
}

pub(crate) fn decode(bytes: &[u8]) -> Result<DecodedPhoto> {
    let reader = ImageReader::new(Cursor::new(bytes)).with_guessed_format()?;
    let format = reader.format();
    if !matches!(format, Some(ImageFormat::Png | ImageFormat::Jpeg)) {
        #[cfg(target_os = "macos")]
        return super::photo_macos::decode_heif(bytes);
        #[cfg(not(target_os = "macos"))]
        return Err(Error::Invalid("Fotoformat nicht unterstützt. JPEG oder PNG verwenden; HEIC/HEIF wird in der macOS- und iOS-App unterstützt.".into()));
    }
    let (source_width, source_height) = reader.into_dimensions()?;
    check_dimensions(source_width.into(), source_height.into())?;
    let image = image::load_from_memory(bytes)?;
    let orientation = exif::Reader::new()
        .read_from_container(&mut Cursor::new(bytes))
        .ok()
        .and_then(|e| {
            e.get_field(exif::Tag::Orientation, exif::In::PRIMARY)
                .and_then(|f| f.value.get_uint(0))
        })
        .unwrap_or(1);
    let image = match orientation {
        2 => image.fliph(),
        3 => image.rotate180(),
        4 => image.flipv(),
        5 => image.rotate90().fliph(),
        6 => image.rotate90(),
        7 => image.rotate90().flipv(),
        8 => image.rotate270(),
        _ => image,
    };
    Ok(DecodedPhoto {
        image,
        source_width,
        source_height,
        orientation,
        source_is_png: format == Some(ImageFormat::Png),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dimensions_are_bounded_before_pixel_allocation() {
        assert!(check_dimensions(10_000, 5_000).is_ok());
        for (w, h) in [(0, 1), (1, 0), (10_000, 5_001), (u64::MAX, 2)] {
            assert!(check_dimensions(w, h).is_err());
        }
    }
}

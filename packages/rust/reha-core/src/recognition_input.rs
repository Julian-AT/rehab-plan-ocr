//! Shared crop-to-tensor preprocessing; no model or platform runtime is needed.
use crate::{Error, Result};
use image::{imageops::FilterType, RgbImage};

pub fn recognition_width(width: u32, height: u32) -> (u32, u32) {
    let resized = ((48. * width as f64 / height.max(1) as f64).ceil() as u32).clamp(8, 3200);
    (resized, resized.max(320).div_ceil(8) * 8)
}

/// Append one BGR/CHW image directly to the caller's batch, preserving its prefix.
/// Padding is normalized zero, and all crops in a batch must share padded width.
pub fn append(crop: &RgbImage, inputs: &mut Vec<f32>) -> Result<(u32, u32)> {
    if crop.width() == 0 || crop.height() == 0 {
        return Err(Error::Invalid("Recognition crop must be nonempty.".into()));
    }
    let (rw, padded) = recognition_width(crop.width(), crop.height());
    let resized = image::imageops::resize(crop, rw, 48, FilterType::Triangle);
    let offset = inputs.len();
    inputs.resize(offset + 3 * (padded * 48) as usize, 0f32);
    for (x, y, p) in resized.enumerate_pixels() {
        for c in 0..3 {
            inputs[offset + c * (padded * 48) as usize + (y * padded + x) as usize] =
                (p[2 - c] as f32 / 255. - 0.5) / 0.5;
        }
    }
    Ok((rw, padded))
}

/// Host-only support for the model-free fixture CLI; excluded from iOS builds.
#[cfg(not(target_os = "ios"))]
pub mod fixture {
    use crate::{Error, Result};
    use image::{ImageFormat, ImageReader, Limits, RgbImage};
    use sha2::{Digest, Sha256};
    use std::{
        fs::File,
        io::{Cursor, Read},
        path::Path,
    };

    pub const MAX_PNG_BYTES: usize = 16 * 1024 * 1024;
    pub const MAX_PIXELS: u64 = 16_000_000;
    pub const MAX_SIDE: u32 = 32_768;

    pub fn decode_png(bytes: &[u8]) -> Result<RgbImage> {
        if bytes.len() > MAX_PNG_BYTES || !bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
            return Err(Error::Invalid(
                "Fixture input must be a PNG of at most 16 MiB.".into(),
            ));
        }
        let mut limits = Limits::default();
        limits.max_image_width = Some(MAX_SIDE);
        limits.max_image_height = Some(MAX_SIDE);
        limits.max_alloc = Some(64 * 1024 * 1024);
        let mut header = ImageReader::with_format(Cursor::new(bytes), ImageFormat::Png);
        header.limits(limits.clone());
        let (width, height) = header.into_dimensions()?;
        if width == 0
            || height == 0
            || width > MAX_SIDE
            || height > MAX_SIDE
            || width as u64 * height as u64 > MAX_PIXELS
        {
            return Err(Error::Invalid(
                "Fixture PNG dimensions exceed the crop limits.".into(),
            ));
        }
        let mut reader = ImageReader::with_format(Cursor::new(bytes), ImageFormat::Png);
        reader.limits(limits);
        Ok(reader.decode()?.into_rgb8())
    }

    /// Stream the producer executable's checksum without a second large allocation.
    pub fn file_sha256(path: &Path) -> Result<String> {
        let mut file = File::open(path)?;
        let mut digest = Sha256::new();
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let read = file.read(&mut buffer)?;
            if read == 0 {
                break;
            }
            digest.update(&buffer[..read]);
        }
        Ok(format!("{:x}", digest.finalize()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    #[test]
    fn width_boundaries_preserve_app_geometry() {
        for (width, height, expected) in [
            (1, 48, (8, 320)),
            (319, 48, (319, 320)),
            (320, 48, (320, 320)),
            (321, 48, (321, 328)),
            (327, 48, (327, 328)),
            (328, 48, (328, 328)),
            (3199, 48, (3199, 3200)),
            (3200, 48, (3200, 3200)),
            (3201, 48, (3200, 3200)),
            (342, 31, (530, 536)),
        ] {
            assert_eq!(recognition_width(width, height), expected);
        }
    }

    #[test]
    fn appends_bgr_planes_and_zero_padding_without_replacing_prefix() {
        let mut input = vec![-0.0f32, 17.];
        let crop = RgbImage::from_pixel(8, 48, Rgb([255, 0, 0]));
        assert_eq!(append(&crop, &mut input).unwrap(), (8, 320));
        assert_eq!(input[0].to_bits(), (-0.0f32).to_bits());
        assert_eq!(input[1], 17.);
        assert_eq!(input.len(), 2 + 3 * 48 * 320);
        for channel in 0..3 {
            for y in 0..48 {
                for x in 0..320 {
                    let expected: f32 = if x >= 8 {
                        0.
                    } else if channel == 2 {
                        1.
                    } else {
                        -1.
                    };
                    assert_eq!(
                        input[2 + channel * 48 * 320 + y * 320 + x].to_bits(),
                        expected.to_bits()
                    );
                }
            }
        }
        let previous = input.iter().map(|v| v.to_bits()).collect::<Vec<_>>();
        append(&RgbImage::from_pixel(8, 48, Rgb([0, 0, 255])), &mut input).unwrap();
        assert_eq!(
            input[..previous.len()]
                .iter()
                .map(|v| v.to_bits())
                .collect::<Vec<_>>(),
            previous
        );
        assert_eq!(input[previous.len()], 1.);
    }

    #[test]
    fn empty_crop_does_not_modify_batch() {
        let mut input = vec![42.];
        assert!(append(&RgbImage::new(0, 48), &mut input).is_err());
        assert_eq!(input, [42.]);
    }

    #[cfg(not(target_os = "ios"))]
    #[test]
    fn fixture_decoder_accepts_png_and_rejects_other_formats_and_oversized_inputs() {
        use image::{DynamicImage, ImageFormat};
        use std::io::Cursor;
        let crop = RgbImage::from_pixel(7, 3, Rgb([4, 5, 6]));
        let mut png = Cursor::new(Vec::new());
        DynamicImage::ImageRgb8(crop.clone())
            .write_to(&mut png, ImageFormat::Png)
            .unwrap();
        assert_eq!(fixture::decode_png(png.get_ref()).unwrap(), crop);
        assert!(fixture::decode_png(b"not a PNG").is_err());
        let mut oversized = vec![0; fixture::MAX_PNG_BYTES + 1];
        oversized[..8].copy_from_slice(b"\x89PNG\r\n\x1a\n");
        assert!(fixture::decode_png(&oversized).is_err());
        let mut too_wide = Cursor::new(Vec::new());
        DynamicImage::ImageRgb8(RgbImage::new(fixture::MAX_SIDE + 1, 1))
            .write_to(&mut too_wide, ImageFormat::Png)
            .unwrap();
        assert!(fixture::decode_png(too_wide.get_ref()).is_err());
    }
}

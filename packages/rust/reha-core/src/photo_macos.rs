//! Local HEIC/HEIF decoding using the macOS ImageIO framework. No subprocess,
//! network transfer or intermediate PNG encode/decode is needed.
use crate::{
    photo::{check_dimensions, DecodedPhoto},
    Error, Result,
};
use core_foundation::{
    base::{CFType, CFTypeRef, TCFType},
    boolean::CFBoolean,
    data::{CFData, CFDataRef},
    dictionary::{CFDictionary, CFDictionaryRef},
    number::CFNumber,
    string::{CFString, CFStringRef},
};
use core_graphics::{
    color_space::{kCGColorSpaceSRGB, CGColorSpace},
    context::CGContext,
    geometry::{CGPoint, CGRect, CGSize},
    image::{CGImage, CGImageAlphaInfo, CGImageByteOrderInfo},
};
use foreign_types::ForeignType;
use std::ptr;

// ImageIO source objects are CFTypes. Create/Copy results are owned by the
// CoreFoundation/CoreGraphics RAII wrappers immediately after null checks.
#[link(name = "ImageIO", kind = "framework")]
extern "C" {
    fn CGImageSourceCreateWithData(data: CFDataRef, options: CFDictionaryRef) -> CFTypeRef;
    fn CGImageSourceGetType(source: CFTypeRef) -> CFStringRef;
    fn CGImageSourceGetPrimaryImageIndex(source: CFTypeRef) -> usize;
    fn CGImageSourceCopyPropertiesAtIndex(
        source: CFTypeRef,
        index: usize,
        options: CFDictionaryRef,
    ) -> CFDictionaryRef;
    fn CGImageSourceCreateThumbnailAtIndex(
        source: CFTypeRef,
        index: usize,
        options: CFDictionaryRef,
    ) -> core_graphics::sys::CGImageRef;
    static kCGImagePropertyPixelWidth: CFStringRef;
    static kCGImagePropertyPixelHeight: CFStringRef;
    static kCGImagePropertyOrientation: CFStringRef;
    static kCGImageSourceShouldCache: CFStringRef;
    static kCGImageSourceCreateThumbnailFromImageAlways: CFStringRef;
    static kCGImageSourceCreateThumbnailWithTransform: CFStringRef;
    static kCGImageSourceThumbnailMaxPixelSize: CFStringRef;
}

pub(crate) fn decode_heif(bytes: &[u8]) -> Result<DecodedPhoto> {
    // SAFETY: All pointers below come from live, retained framework objects or
    // documented CFString constants. Nulls and dictionary value types are checked
    // before wrapping, and every Create/Copy result is released exactly once.
    unsafe {
        let data = CFData::from_buffer(bytes);
        let source_options = CFDictionary::from_CFType_pairs(&[(
            CFString::wrap_under_get_rule(kCGImageSourceShouldCache),
            CFBoolean::false_value().as_CFType(),
        )]);
        let source = CGImageSourceCreateWithData(
            data.as_concrete_TypeRef(),
            source_options.as_concrete_TypeRef(),
        );
        if source.is_null() {
            return Err(unreadable());
        }
        let source = CFType::wrap_under_create_rule(source);
        let kind = CGImageSourceGetType(source.as_CFTypeRef());
        if kind.is_null() {
            return Err(unreadable());
        }
        let kind = CFString::wrap_under_get_rule(kind).to_string();
        if !["public.heic", "public.heif", "public.heics", "public.heifs"].contains(&kind.as_str())
        {
            return Err(Error::Invalid(
                "Fotoformat nicht unterstützt. JPEG, PNG, HEIC oder HEIF verwenden.".into(),
            ));
        }
        // HEIF may contain auxiliary/depth images. Always select the primary photo.
        let index = CGImageSourceGetPrimaryImageIndex(source.as_CFTypeRef());
        let properties =
            CGImageSourceCopyPropertiesAtIndex(source.as_CFTypeRef(), index, ptr::null());
        if properties.is_null() {
            return Err(unreadable());
        }
        let properties: CFDictionary<CFString, CFType> =
            CFDictionary::wrap_under_create_rule(properties);
        let number = |key| {
            properties
                .find(CFString::wrap_under_get_rule(key))
                .and_then(|v| v.downcast::<CFNumber>())
                .and_then(|n| n.to_i64())
        };
        let width = number(kCGImagePropertyPixelWidth)
            .filter(|v| *v > 0)
            .ok_or_else(unreadable)? as u64;
        let height = number(kCGImagePropertyPixelHeight)
            .filter(|v| *v > 0)
            .ok_or_else(unreadable)? as u64;
        check_dimensions(width, height)?;
        let orientation = number(kCGImagePropertyOrientation)
            .filter(|v| (1..=8).contains(v))
            .unwrap_or(1) as u32;
        // Despite the API name this decodes the full primary image, never the
        // embedded preview. ImageIO applies HEIF/EXIF rotation and reflection once.
        let options = CFDictionary::from_CFType_pairs(&[
            (
                CFString::wrap_under_get_rule(kCGImageSourceCreateThumbnailFromImageAlways),
                CFBoolean::true_value().as_CFType(),
            ),
            (
                CFString::wrap_under_get_rule(kCGImageSourceCreateThumbnailWithTransform),
                CFBoolean::true_value().as_CFType(),
            ),
            (
                CFString::wrap_under_get_rule(kCGImageSourceThumbnailMaxPixelSize),
                CFNumber::from(width.max(height) as i64).as_CFType(),
            ),
        ]);
        let image = CGImageSourceCreateThumbnailAtIndex(
            source.as_CFTypeRef(),
            index,
            options.as_concrete_TypeRef(),
        );
        if image.is_null() {
            return Err(unreadable());
        }
        let image = CGImage::from_ptr(image);
        let (w, h) = (image.width(), image.height());
        check_dimensions(w as u64, h as u64)?;
        let colors = CGColorSpace::create_with_name(kCGColorSpaceSRGB).ok_or_else(unreadable)?;
        let mut context = CGContext::create_bitmap_context(
            None,
            w,
            h,
            8,
            w * 4,
            &colors,
            CGImageAlphaInfo::CGImageAlphaNoneSkipLast as u32
                | CGImageByteOrderInfo::CGImageByteOrder32Big as u32,
        );
        let bounds = CGRect::new(&CGPoint::new(0., 0.), &CGSize::new(w as f64, h as f64));
        context.set_rgb_fill_color(1., 1., 1., 1.);
        context.fill_rect(bounds);
        context.draw_image(bounds, &image);
        let rgb: Vec<u8> = context
            .data()
            .as_chunks::<4>()
            .0
            .iter()
            .flat_map(|pixel| pixel[..3].iter().copied())
            .collect();
        let image = image::RgbImage::from_raw(w as u32, h as u32, rgb).ok_or_else(unreadable)?;
        Ok(DecodedPhoto {
            image: image::DynamicImage::ImageRgb8(image),
            source_width: width as u32,
            source_height: height as u32,
            orientation,
            source_is_png: false,
        })
    }
}

fn unreadable() -> Error {
    Error::Invalid("HEIC/HEIF-Foto konnte nicht gelesen werden. Die Datei ist beschädigt oder enthält kein unterstütztes Foto.".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn heif_uses_primary_photo_instead_of_first_image() {
        let photo = decode_heif(include_bytes!(
            "../../../../tests/fixtures/heic/multiple-images.heic"
        ))
        .unwrap();
        let image = photo.image.into_rgb8();
        assert_eq!(image.dimensions(), (32, 48));
        let pixel = image.get_pixel(16, 24);
        assert!(pixel[2] > 220 && pixel[0] < 40 && pixel[1] < 40);
    }

    #[test]
    fn heif_preserves_full_resolution_and_all_eight_orientations() {
        let input = image::RgbImage::from_fn(96, 64, |x, y| {
            image::Rgb(match (x < 48, y < 32) {
                (true, true) => [240, 20, 20],
                (false, true) => [20, 220, 20],
                (true, false) => [20, 20, 240],
                (false, false) => [230, 220, 20],
            })
        });
        let input = image::DynamicImage::ImageRgb8(input);
        for orientation in 1..=8 {
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(format!(
                "../../../tests/fixtures/heic/orientation-{orientation}.heic"
            ));
            let decoded = decode_heif(&std::fs::read(path).unwrap())
                .unwrap()
                .image
                .into_rgb8();
            let expected = match orientation {
                2 => input.fliph(),
                3 => input.rotate180(),
                4 => input.flipv(),
                5 => input.rotate90().fliph(),
                6 => input.rotate90(),
                7 => input.rotate90().flipv(),
                8 => input.rotate270(),
                _ => input.clone(),
            }
            .into_rgb8();
            assert_eq!(
                decoded.dimensions(),
                expected.dimensions(),
                "orientation {orientation}"
            );
            let (w, h) = decoded.dimensions();
            for (x, y) in [
                (w / 4, h / 4),
                (3 * w / 4, h / 4),
                (w / 4, 3 * h / 4),
                (3 * w / 4, 3 * h / 4),
            ] {
                let actual = decoded.get_pixel(x, y);
                let expected = expected.get_pixel(x, y);
                assert!(
                    (0..3).all(|c| actual[c].abs_diff(expected[c]) < 12),
                    "orientation {orientation}, ({x},{y}): {actual:?} vs {expected:?}"
                );
            }
        }
    }

    #[test]
    fn invalid_or_truncated_heif_returns_an_error() {
        assert!(decode_heif(b"not an image").is_err());
        assert!(decode_heif(b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00heicmif1").is_err());
    }
}

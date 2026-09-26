use crate::{contracts::Point, Error, Result};
pub const IDENTITY: [f64; 9] = [1., 0., 0., 0., 1., 0., 0., 0., 1.];

/// Conservative page detection: a large convex white quadrilateral, wholly
/// inside the photograph, with darker exterior evidence on every edge. Partial
/// pages, white backgrounds and ambiguous borders deliberately use text baselines.
pub fn paper_quad(image: &image::RgbImage) -> Option<[Point; 4]> {
    let small = image::imageops::thumbnail(image, 600, 600);
    let gray = image::DynamicImage::ImageRgb8(small).to_luma8();
    let (w, h) = gray.dimensions();
    let binary = image::GrayImage::from_fn(w, h, |x, y| {
        image::Luma([if gray.get_pixel(x, y)[0] > 170 {
            255
        } else {
            0
        }])
    });
    let mut candidates = vec![];
    for contour in imageproc::contours::find_contours::<i32>(&binary) {
        if contour.border_type != imageproc::contours::BorderType::Outer {
            continue;
        }
        let p = imageproc::geometry::approximate_polygon_dp(&contour.points, 4., true);
        if p.len() != 4
            || p.iter()
                .any(|p| p.x < 4 || p.y < 4 || p.x > w as i32 - 5 || p.y > h as i32 - 5)
        {
            continue;
        }
        let mut quad: Vec<_> = p
            .iter()
            .map(|p| Point {
                x: p.x as f64,
                y: p.y as f64,
            })
            .collect();
        let center = Point {
            x: quad.iter().map(|p| p.x).sum::<f64>() / 4.,
            y: quad.iter().map(|p| p.y).sum::<f64>() / 4.,
        };
        quad.sort_by(|a, b| {
            (a.y - center.y)
                .atan2(a.x - center.x)
                .total_cmp(&(b.y - center.y).atan2(b.x - center.x))
        });
        let first = (0..4)
            .min_by(|a, b| (quad[*a].x + quad[*a].y).total_cmp(&(quad[*b].x + quad[*b].y)))
            .unwrap();
        quad.rotate_left(first);
        let area = (0..4)
            .map(|i| quad[i].x * quad[(i + 1) % 4].y - quad[(i + 1) % 4].x * quad[i].y)
            .sum::<f64>()
            .abs()
            / 2.;
        if area < (w * h) as f64 * 0.60 {
            continue;
        }
        let intensity = |p: Point| {
            gray.get_pixel(
                p.x.round().clamp(0., (w - 1) as f64) as u32,
                p.y.round().clamp(0., (h - 1) as f64) as u32,
            )[0] as f64
        };
        let supported = (0..4).all(|i| {
            let (a, b) = (quad[i], quad[(i + 1) % 4]);
            let contrast = (1..5)
                .map(|j| {
                    let p = Point {
                        x: a.x + (b.x - a.x) * j as f64 / 5.,
                        y: a.y + (b.y - a.y) * j as f64 / 5.,
                    };
                    let d = distance(&p, &center);
                    let dx = (center.x - p.x) / d * 5.;
                    let dy = (center.y - p.y) / d * 5.;
                    intensity(Point {
                        x: p.x + dx,
                        y: p.y + dy,
                    }) - intensity(Point {
                        x: p.x - dx,
                        y: p.y - dy,
                    })
                })
                .sum::<f64>()
                / 4.;
            contrast > 35.
        });
        if supported {
            candidates.push((area, quad));
        }
    }
    candidates.sort_by(|a, b| b.0.total_cmp(&a.0));
    let (_, quad) = candidates.first()?;
    let mapped: Vec<_> = quad
        .iter()
        .map(|p| Point {
            x: p.x * image.width() as f64 / w as f64,
            y: p.y * image.height() as f64 / h as f64,
        })
        .collect();
    let quad: [Point; 4] = mapped.try_into().ok()?;
    homography(&quad, &rect(0., 0., 100., 100.).try_into().unwrap()).ok()?;
    Some(quad)
}
pub fn distance(a: &Point, b: &Point) -> f64 {
    ((a.x - b.x).powi(2) + (a.y - b.y).powi(2)).sqrt()
}
pub fn inside(polygon: &[Point], p: &Point) -> bool {
    let mut sign: f64 = 0.;
    for i in 0..polygon.len() {
        let a = &polygon[i];
        let b = &polygon[(i + 1) % polygon.len()];
        let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
        if cross.abs() < 1e-6 {
            continue;
        }
        if sign != 0. && sign.signum() != cross.signum() {
            return false;
        }
        sign = cross;
    }
    polygon.len() >= 3
}
pub fn rectify_with_transform(
    page: &image::RgbImage,
    polygon: &[Point],
) -> Result<(image::RgbImage, [f64; 9])> {
    let from: [Point; 4] = polygon
        .try_into()
        .map_err(|_| Error::Invalid("Vier Textpunkte erforderlich.".into()))?;
    let w = distance(&from[0], &from[1])
        .max(distance(&from[3], &from[2]))
        .ceil() as u32;
    let h = distance(&from[0], &from[3])
        .max(distance(&from[1], &from[2]))
        .ceil() as u32;
    if w < 2 || h < 2 || w as u64 * h as u64 > 50_000_000 {
        return Err(Error::Invalid("Ungültiger Textausschnitt.".into()));
    }
    let to = rect(0., 0., (w - 1) as f64, (h - 1) as f64)
        .try_into()
        .unwrap();
    let m = homography(&from, &to)?;
    let projection =
        imageproc::geometric_transformations::Projection::from_matrix(m.map(|v| v as f32))
            .ok_or_else(|| Error::Invalid("Textgeometrie nicht entzerrbar.".into()))?;
    let mut crop = image::RgbImage::new(w, h);
    imageproc::geometric_transformations::warp_into(
        page,
        &projection,
        imageproc::geometric_transformations::Interpolation::Bilinear,
        image::Rgb([255, 255, 255]),
        &mut crop,
    );
    Ok((crop, inverse(&m)?))
}
pub fn rectify(page: &image::RgbImage, polygon: &[Point]) -> Result<image::RgbImage> {
    let (crop, _) = rectify_with_transform(page, polygon)?;
    Ok(if crop.height() as f64 / crop.width() as f64 >= 1.5 {
        image::imageops::rotate270(&crop)
    } else {
        crop
    })
}
pub fn map(m: &[f64; 9], p: &Point) -> Point {
    let d = m[6] * p.x + m[7] * p.y + m[8];
    Point {
        x: (m[0] * p.x + m[1] * p.y + m[2]) / d,
        y: (m[3] * p.x + m[4] * p.y + m[5]) / d,
    }
}
pub fn multiply(a: &[f64; 9], b: &[f64; 9]) -> [f64; 9] {
    let mut c = [0.; 9];
    for i in 0..3 {
        for j in 0..3 {
            for k in 0..3 {
                c[i * 3 + j] += a[i * 3 + k] * b[k * 3 + j];
            }
        }
    }
    c
}
pub fn inverse(m: &[f64; 9]) -> Result<[f64; 9]> {
    let [a, b, c, d, e, f, g, h, i] = *m;
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if det.abs() < 1e-9 {
        return Err(Error::Invalid("Page corners are degenerate".into()));
    }
    Ok([
        e * i - f * h,
        c * h - b * i,
        b * f - c * e,
        f * g - d * i,
        a * i - c * g,
        c * d - a * f,
        d * h - e * g,
        b * g - a * h,
        a * e - b * d,
    ]
    .map(|x| x / det))
}
pub fn rect(x: f64, y: f64, width: f64, height: f64) -> Vec<Point> {
    vec![
        Point { x, y },
        Point { x: x + width, y },
        Point {
            x: x + width,
            y: y + height,
        },
        Point { x, y: y + height },
    ]
}
pub fn bounds(points: &[Point]) -> (f64, f64, f64, f64) {
    points.iter().fold(
        (
            f64::INFINITY,
            f64::INFINITY,
            f64::NEG_INFINITY,
            f64::NEG_INFINITY,
        ),
        |(x, y, r, b), p| (x.min(p.x), y.min(p.y), r.max(p.x), b.max(p.y)),
    )
}
pub fn rotation(turns: u8, w: u32, h: u32) -> [f64; 9] {
    match turns % 4 {
        1 => [0., -1., h as f64, 1., 0., 0., 0., 0., 1.],
        2 => [-1., 0., w as f64, 0., -1., h as f64, 0., 0., 1.],
        3 => [0., 1., 0., -1., 0., w as f64, 0., 0., 1.],
        _ => IDENTITY,
    }
}

pub fn homography(from: &[Point; 4], to: &[Point; 4]) -> Result<[f64; 9]> {
    for points in [from, to] {
        let mut sign = 0.;
        for i in 0..4 {
            let (a, b, c) = (points[i], points[(i + 1) % 4], points[(i + 2) % 4]);
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
            if !cross.is_finite() || cross.abs() < 1e-6 || (sign != 0. && cross * sign < 0.) {
                return Err(Error::Invalid(
                    "Seitenpunkte müssen ein konvexes Viereck in umlaufender Reihenfolge bilden."
                        .into(),
                ));
            }
            sign = cross;
        }
    }
    let mut a = [[0.; 9]; 8];
    for i in 0..4 {
        let (x, y, u, v) = (from[i].x, from[i].y, to[i].x, to[i].y);
        a[2 * i] = [x, y, 1., 0., 0., 0., -u * x, -u * y, u];
        a[2 * i + 1] = [0., 0., 0., x, y, 1., -v * x, -v * y, v];
    }
    for col in 0..8 {
        let pivot = (col..8)
            .max_by(|aidx, bidx| a[*aidx][col].abs().total_cmp(&a[*bidx][col].abs()))
            .unwrap();
        a.swap(col, pivot);
        let d = a[col][col];
        if d.abs() < 1e-9 {
            return Err(Error::Invalid("Ungültige Seitenpunkte.".into()));
        }
        for value in a[col].iter_mut().skip(col) {
            *value /= d;
        }
        let pivot_row = a[col];
        for (index, row) in a.iter_mut().enumerate() {
            if index == col {
                continue;
            }
            let factor = row[col];
            for (value, pivot) in row.iter_mut().zip(pivot_row).skip(col) {
                *value -= factor * pivot;
            }
        }
    }
    let mut m = [0.; 9];
    for i in 0..8 {
        m[i] = a[i][8];
    }
    m[8] = 1.;
    Ok(m)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn automatic_page_corners_require_four_visible_contrasting_edges() {
        let mut photo = image::RgbImage::from_pixel(500, 600, image::Rgb([70, 70, 70]));
        for y in 28..572 {
            for x in 28..472 {
                photo.put_pixel(x, y, image::Rgb([245, 245, 245]));
            }
        }
        let q = paper_quad(&photo).unwrap();
        assert!((q[0].x - 28.).abs() < 2.);
        assert!(paper_quad(&image::RgbImage::from_pixel(
            500,
            600,
            image::Rgb([245, 245, 245])
        ))
        .is_none());
        for y in 0..600 {
            for x in 0..100 {
                photo.put_pixel(x, y, image::Rgb([245, 245, 245]));
            }
        }
        assert!(paper_quad(&photo).is_none());
    }
    #[test]
    fn field_rectification_samples_exact_source_polygon_and_maps_back() {
        let source = image::RgbImage::from_fn(180, 180, |x, y| image::Rgb([x as u8, y as u8, 0]));
        let quad = [
            Point { x: 40., y: 30. },
            Point { x: 130., y: 60. },
            Point { x: 115., y: 115. },
            Point { x: 25., y: 80. },
        ];
        let (crop, to_original) = rectify_with_transform(&source, &quad).unwrap();
        for (x, y) in [
            (2, 2),
            (crop.width() / 2, crop.height() / 2),
            (crop.width() - 3, crop.height() - 3),
        ] {
            let p = map(
                &to_original,
                &Point {
                    x: x as f64,
                    y: y as f64,
                },
            );
            let pixel = crop.get_pixel(x, y);
            assert!((pixel[0] as f64 - p.x).abs() < 1.2 && (pixel[1] as f64 - p.y).abs() < 1.2);
        }
        let mirrored = [quad[1], quad[0], quad[3], quad[2]];
        let (crop, m) = rectify_with_transform(&source, &mirrored).unwrap();
        let p = map(&m, &Point { x: 0., y: 0. });
        assert!((p.x - 130.).abs() < 1e-6);
        assert!(crop.get_pixel(2, 2)[0] > crop.get_pixel(crop.width() - 3, 2)[0]);
    }
    #[test]
    fn perspective_round_trip() {
        let m = [1.2, 0.1, 25., -0.1, 0.8, 37., 0.0001, 0.0003, 1.];
        let p = Point { x: 213., y: 307. };
        let q = map(&inverse(&m).unwrap(), &map(&m, &p));
        assert!((q.x - p.x).abs() < 1e-7 && (q.y - p.y).abs() < 1e-7);
    }
    #[test]
    fn rotation_round_trip() {
        for turns in 0..4 {
            let m = rotation(turns, 900, 1200);
            let p = Point { x: 43., y: 87. };
            let q = map(&inverse(&m).unwrap(), &map(&m, &p));
            assert_eq!(p, q);
        }
    }
    #[test]
    fn rejects_crossed_or_collinear_page_corners() {
        let page: [Point; 4] = rect(0., 0., 900., 1200.).try_into().unwrap();
        let mut crossed = page;
        crossed.swap(1, 2);
        assert!(homography(&crossed, &page).is_err());
        let mut flat = page;
        flat[1] = Point { x: 0., y: 600. };
        flat[2] = Point { x: 0., y: 1200. };
        assert!(homography(&flat, &page).is_err());
        let m = homography(&page, &page).unwrap();
        assert!((map(&m, &page[2]).x - 900.).abs() < 1e-6);
    }
}

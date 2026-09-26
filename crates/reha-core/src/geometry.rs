use crate::{contracts::Point, Error, Result};
pub const IDENTITY: [f64; 9] = [1., 0., 0., 0., 1., 0., 0., 0., 1.];
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

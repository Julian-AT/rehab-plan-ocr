use crate::{
    contracts::{Observation, Point, Region},
    geometry::bounds,
};

/// Robust text baselines supply table skew even when no page edge is visible.
/// Header anchors are a fallback for old axis-aligned observations.
fn table_transform(observations: &[Observation], regions: &[Region]) -> [f64; 9] {
    let mut slopes = vec![];
    for r in regions
        .iter()
        .filter(|r| r.polygon.len() == 4 && (r.kind == "text" || r.kind == "uncertain_text"))
    {
        let p = &r.polygon;
        for (a, b) in [(p[0], p[1]), (p[3], p[2])] {
            let dx = b.x - a.x;
            let dy = b.y - a.y;
            if dx.abs() > 50. && dy.abs() / dx.abs() < 0.25 {
                slopes.push(dy / dx);
            }
        }
    }
    if slopes.iter().filter(|s| s.abs() > 0.0001).count() < 4 {
        slopes.clear();
        let headers: Vec<_> = observations
            .iter()
            .filter(|o| {
                ["uhrzeit", "therapie", "raum", "therapeut"]
                    .contains(&o.text.trim().to_lowercase().as_str())
            })
            // Resolve each observation once, retaining the existing treatment of
            // missing, repeated and multiple region references. Looking it up
            // again for every pair makes a dense page cubic in its region count.
            .map(|o| observation_bounds(o, regions))
            .collect();
        for (i, &(ax, ay, _, ab)) in headers.iter().enumerate() {
            for &(bx, by, _, bb) in headers.iter().skip(i + 1) {
                let dx = bx - ax;
                let dy = (by + bb - ay - ab) / 2.;
                if dx.abs() > 100. && dy.abs() / dx.abs() < 0.2 {
                    slopes.push(dy / dx);
                }
            }
        }
    }
    slopes.sort_by(f64::total_cmp);
    let slope = slopes.get(slopes.len() / 2).copied().unwrap_or(0.);
    [1., 0., 0., -slope, 1., 0., 0., 0., 1.]
}
fn transformed_regions(regions: &[Region], m: &[f64; 9]) -> Vec<Region> {
    regions
        .iter()
        .cloned()
        .map(|mut r| {
            r.polygon = r
                .polygon
                .iter()
                .map(|p| crate::geometry::map(m, p))
                .collect();
            r
        })
        .collect()
}

/// Residual baseline slope varies down a curved/perspective table. A local
/// median only applies with enough independent text boxes; sparse pages retain
/// the global/header fallback. Coordinates remain invertible to source pixels.
pub(super) struct TableAlignment {
    base: [f64; 9],
    samples: Vec<(f64, f64)>,
}
impl TableAlignment {
    pub(super) fn new(observations: &[Observation], regions: &[Region]) -> Self {
        let base = table_transform(observations, regions);
        let aligned = transformed_regions(regions, &base);
        let samples: Vec<(f64, f64)> = aligned
            .iter()
            .filter(|r| r.polygon.len() == 4 && r.kind == "text")
            .filter_map(|r| {
                let p = &r.polygon;
                let dx = p[1].x - p[0].x;
                let slope = (p[1].y - p[0].y) / dx;
                (dx > 70. && slope.abs() < 0.06).then_some(((p[0].y + p[2].y) / 2., slope))
            })
            .collect();
        if samples.len() < 12 {
            return Self {
                base,
                samples: vec![],
            };
        }
        let width = aligned
            .iter()
            .flat_map(|r| r.polygon.iter())
            .map(|p| p.x.abs())
            .fold(1., f64::max);
        let mut positions: Vec<_> = samples.iter().map(|s| s.0).collect();
        positions.sort_by(f64::total_cmp);
        let mut knots: Vec<(f64, f64)> = vec![];
        for i in 0..5 {
            let y = positions[i * (positions.len() - 1) / 4];
            if knots.last().is_some_and(|k| (k.0 - y).abs() < 1.) {
                continue;
            }
            let mut nearest = samples.clone();
            nearest.sort_by(|a, b| (a.0 - y).abs().total_cmp(&(b.0 - y).abs()));
            let mut values: Vec<_> = nearest.iter().take(12).map(|s| s.1).collect();
            values.sort_by(f64::total_cmp);
            let mut slope = if values[values.len() * 3 / 4] - values[values.len() / 4] > 0.025 {
                0.
            } else {
                values[values.len() / 2]
            };
            if let Some((py, ps)) = knots.last() {
                // Bound the derivative so the warp cannot fold rows at any x.
                let change = (y - py) * 0.25 / width;
                slope = slope.clamp(ps - change, ps + change);
            }
            knots.push((y, slope));
        }
        Self {
            base,
            samples: knots,
        }
    }
    fn slope(&self, y: f64) -> f64 {
        let Some(first) = self.samples.first() else {
            return 0.;
        };
        if y <= first.0 {
            return first.1;
        }
        for pair in self.samples.windows(2) {
            let (a, b) = (pair[0], pair[1]);
            if y <= b.0 {
                return a.1 + (b.1 - a.1) * (y - a.0) / (b.0 - a.0);
            }
        }
        self.samples.last().unwrap().1
    }
    fn forward(&self, p: &Point) -> Point {
        let mut p = crate::geometry::map(&self.base, p);
        p.y -= self.slope(p.y) * p.x;
        p
    }
    pub(super) fn backward(&self, p: &Point) -> Point {
        let mut q = *p;
        if let Some(first) = self.samples.first() {
            q.y = p.y + self.samples.last().unwrap().1 * p.x;
            if p.y <= first.0 - first.1 * p.x {
                q.y = p.y + first.1 * p.x;
            } else {
                for pair in self.samples.windows(2) {
                    let (a, b) = (pair[0], pair[1]);
                    if p.y <= b.0 - b.1 * p.x {
                        let k = (b.1 - a.1) / (b.0 - a.0);
                        q.y = (p.y + p.x * (a.1 - k * a.0)) / (1. - k * p.x);
                        break;
                    }
                }
            }
        }
        crate::geometry::map(
            &crate::geometry::inverse(&self.base).unwrap_or(crate::geometry::IDENTITY),
            &q,
        )
    }
    pub(super) fn regions(&self, regions: &[Region]) -> Vec<Region> {
        regions
            .iter()
            .cloned()
            .map(|mut r| {
                r.polygon = r.polygon.iter().map(|p| self.forward(p)).collect();
                r
            })
            .collect()
    }
}

pub(super) fn observation_bounds(o: &Observation, regions: &[Region]) -> (f64, f64, f64, f64) {
    let points: Vec<_> = regions
        .iter()
        .filter(|r| o.region_ids.contains(&r.id))
        .flat_map(|r| r.polygon.clone())
        .collect();
    bounds(&points)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::tests::header_fixture;

    #[test]
    fn cached_header_bounds_preserve_legacy_pairwise_transform() {
        // The pre-optimization fallback is retained here as a numerical oracle.
        // In particular, missing references and multiple boxes must not acquire
        // different coordinates through a new lookup/deduplication policy.
        fn previous_transform(observations: &[Observation], regions: &[Region]) -> [f64; 9] {
            let headers: Vec<_> = observations
                .iter()
                .filter(|o| {
                    ["uhrzeit", "therapie", "raum", "therapeut"]
                        .contains(&o.text.trim().to_lowercase().as_str())
                })
                .collect();
            let mut slopes = vec![];
            for (i, a) in headers.iter().enumerate() {
                let (ax, ay, _, ab) = observation_bounds(a, regions);
                for b in headers.iter().skip(i + 1) {
                    let (bx, by, _, bb) = observation_bounds(b, regions);
                    let dx = bx - ax;
                    let dy = (by + bb - ay - ab) / 2.;
                    if dx.abs() > 100. && dy.abs() / dx.abs() < 0.2 {
                        slopes.push(dy / dx);
                    }
                }
            }
            slopes.sort_by(f64::total_cmp);
            let slope = slopes.get(slopes.len() / 2).copied().unwrap_or(0.);
            [1., 0., 0., -slope, 1., 0., 0., 0., 1.]
        }

        for count in [0, 1, 4, 64] {
            for slope in [-0.14, 0., 0.07] {
                let (mut observations, mut regions) = header_fixture(count, slope);
                for variant in 0..3 {
                    if variant == 1 && count >= 4 {
                        observations[0].region_ids.push("r1".into());
                        observations[1].region_ids = vec!["missing".into()];
                        observations[2].region_ids.push("r2".into());
                        observations[3].text = "Raum 107".into();
                        regions.push(regions[0].clone());
                    } else if variant == 2 {
                        observations.reverse();
                        regions.reverse();
                    }
                    assert_eq!(
                        table_transform(&observations, &regions).map(f64::to_bits),
                        previous_transform(&observations, &regions).map(f64::to_bits),
                        "count={count}, slope={slope}, variant={variant}"
                    );
                }
            }
        }
    }

    #[test]
    fn varying_table_baselines_remain_invertible() {
        let alignment = TableAlignment {
            base: [1., 0., 0., -0.07, 1., 0., 0., 0., 1.],
            samples: vec![(0., 0.01), (500., -0.02), (1000., 0.03)],
        };
        for y in [-100., 0., 150., 500., 750., 1100.] {
            for x in [0., 100., 1200.] {
                let p = Point { x, y };
                let q = alignment.backward(&alignment.forward(&p));
                assert!((q.y - y).abs() < 1e-7 && (q.x - x).abs() < 1e-7);
            }
        }
    }
}

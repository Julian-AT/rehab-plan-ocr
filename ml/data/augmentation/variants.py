"""Deterministic geometry and visibility shared by augmentation pixels and labels."""

import hashlib
import json
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

AUGMENTATION_VERSION = 3


def _step_matrix(recipe, w, h):
    if "turn" in recipe:
        return [
            ([1, 0, 0, 0, 1, 0, 0, 0, 1], (w, h)),
            ([0, -1, h, 1, 0, 0, 0, 0, 1], (h, w)),
            ([-1, 0, w, 0, -1, h, 0, 0, 1], (w, h)),
            ([0, 1, 0, -1, 0, w, 0, 0, 1], (h, w)),
        ][recipe["turn"]]
    if recipe.get("mirror") == "horizontal":
        return [-1, 0, w, 0, 1, 0, 0, 0, 1], (w, h)
    if recipe.get("mirror") == "vertical":
        return [1, 0, 0, 0, -1, h, 0, 0, 1], (w, h)
    if "angle" in recipe:
        angle = math.radians(recipe["angle"])
        c, s = math.cos(angle), math.sin(angle)
        return [
            c,
            -s,
            (1 - c) * w / 2 + s * h / 2,
            s,
            c,
            (1 - c) * h / 2 - s * w / 2,
            0,
            0,
            1,
        ], (w, h)
    if "perspective" in recipe:
        p = recipe["perspective"]
        return [1, 0, 0, p * h / w, 1, 0, p / w, 0, 1], (w, h)
    if "shear" in recipe:
        shear = recipe["shear"]
        return [1, shear, -shear * h / 2, 0, 1, 0, 0, 0, 1], (w, h)
    scale = recipe.get("scale", 1)
    return [scale, 0, 0, 0, scale, 0, 0, 0, 1], (round(w * scale), round(h * scale))


def matrix(recipe, w, h):
    result, size = _step_matrix({}, w, h)
    for key in ["turn", "mirror", "angle", "perspective", "shear", "scale"]:
        if key not in recipe:
            continue
        step, size = _step_matrix({key: recipe[key]}, *size)
        result = [
            sum(step[r * 3 + k] * result[k * 3 + c] for k in range(3))
            for r in range(3)
            for c in range(3)
        ]
    if "crop" in recipe:
        left, top, right, bottom = recipe["crop"]
        if (
            not all(0 <= v < 1 for v in [left, top, right, bottom])
            or left + right >= 1
            or top + bottom >= 1
        ):
            raise ValueError("Crop margins must leave a visible image")
        x, y = round(size[0] * left), round(size[1] * top)
        result = (
            [result[c] - x * result[6 + c] for c in range(3)]
            + [result[3 + c] - y * result[6 + c] for c in range(3)]
            + result[6:]
        )
        size = (size[0] - x - round(size[0] * right), size[1] - y - round(size[1] * bottom))
    if min(size) <= 0 or not all(math.isfinite(v) for v in result):
        raise ValueError("Invalid augmentation geometry")
    return result, size


def inverse(m):
    a, b, c, d, e, f, g, h, i = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [
        v / det
        for v in [
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
    ]


def transform(m, polygon):
    return [
        {
            "x": (m[0] * p["x"] + m[1] * p["y"] + m[2]) / (m[6] * p["x"] + m[7] * p["y"] + m[8]),
            "y": (m[3] * p["x"] + m[4] * p["y"] + m[5]) / (m[6] * p["x"] + m[7] * p["y"] + m[8]),
        }
        for p in polygon
    ]


def clip(polygon, size):
    """Visible polygon; the separate projected polygon retains exact inverse mapping."""
    result = polygon
    for axis, boundary, lower in [
        ("x", 0, True),
        ("x", size[0], False),
        ("y", 0, True),
        ("y", size[1], False),
    ]:
        output = []
        for previous, current in zip(result[-1:] + result[:-1], result):
            before = previous[axis] >= boundary if lower else previous[axis] <= boundary
            after = current[axis] >= boundary if lower else current[axis] <= boundary
            if before != after:
                fraction = (boundary - previous[axis]) / (current[axis] - previous[axis])
                output.append(
                    {
                        key: previous[key] + fraction * (current[key] - previous[key])
                        for key in ["x", "y"]
                    }
                )
            if after:
                output.append(current)
        result = output
    unique = []
    for point in result:
        if not unique or point != unique[-1]:
            unique.append(point)
    if len(unique) > 1 and unique[0] == unique[-1]:
        unique.pop()
    area = (
        abs(
            sum(
                a["x"] * b["y"] - a["y"] * b["x"] for a, b in zip(unique[-1:] + unique[:-1], unique)
            )
        )
        / 2
    )
    return unique if area > 1e-7 else []


def _cross(a, b, c):
    return (b["x"] - a["x"]) * (c["y"] - a["y"]) - (b["y"] - a["y"]) * (c["x"] - a["x"])


def inside(polygon, container):
    def contains(p):
        result = False
        for a, b in zip(container[-1:] + container[:-1], container):
            if (
                abs(_cross(a, b, p)) < 1e-7
                and min(a["x"], b["x"]) <= p["x"] <= max(a["x"], b["x"])
                and min(a["y"], b["y"]) <= p["y"] <= max(a["y"], b["y"])
            ):
                return True
            if (a["y"] > p["y"]) != (b["y"] > p["y"]) and p["x"] < (b["x"] - a["x"]) * (
                p["y"] - a["y"]
            ) / (b["y"] - a["y"]) + a["x"]:
                result = not result
        return result

    if not polygon or not all(contains(p) for p in polygon):
        return False
    # Corners alone are insufficient for a concave privacy boundary.
    for a, b in zip(polygon[-1:] + polygon[:-1], polygon):
        for c, d in zip(container[-1:] + container[:-1], container):
            if (
                _cross(a, b, c) * _cross(a, b, d) < -1e-7
                and _cross(c, d, a) * _cross(c, d, b) < -1e-7
            ):
                return False
    return True


def obstructions(recipe, size):
    areas = []
    if "cut" in recipe:
        areas.append(((int(size[0] * recipe["cut"]), 0, size[0], size[1]), "cropped"))
    if recipe.get("cover"):
        areas.append(
            (
                (
                    int(size[0] * 0.48),
                    int(size[1] * 0.42),
                    int(size[0] * 0.56),
                    int(size[1] * 0.64),
                ),
                "illegible",
            )
        )
    if "glare" in recipe:
        x0, y0, x1, y1 = recipe["glare"]
        areas.append(
            (
                (int(size[0] * x0), int(size[1] * y0), int(size[0] * x1), int(size[1] * y1)),
                "illegible",
            )
        )
    return areas


def visibility(polygon, source, recipe, m, size, state):
    p = transform(m, polygon)
    xs, ys = [v["x"] for v in p], [v["y"] for v in p]
    if (
        not inside(polygon, source["table_polygon"])
        or min(xs) < 0
        or min(ys) < 0
        or max(xs) > size[0]
        or max(ys) > size[1]
    ):
        return p, "cropped"
    for area, obstruction_state in obstructions(recipe, size):
        if max(xs) > area[0] and min(xs) < area[2] and max(ys) > area[1] and min(ys) < area[3]:
            return p, obstruction_state
    return p, state


def variant(image, ref, recipe):
    source = ref["sources"][0]
    if image.size != (source["width"], source["height"]):
        raise ValueError("Source dimensions differ from the approved geometry")
    # Patient/header data outside the approved table are never present in exports.
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).polygon(
        [(p["x"], p["y"]) for p in ref["sources"][0]["table_polygon"]], fill=255
    )
    image = Image.composite(image, Image.new("RGB", image.size, "white"), mask)
    m, size = matrix(recipe, *image.size)
    inv = inverse(m)
    output = image.transform(
        size,
        Image.Transform.PERSPECTIVE,
        [v / inv[8] for v in inv[:8]],
        Image.Resampling.BICUBIC,
        fillcolor="white",
    )
    for key, enhancer in [
        ("brightness", ImageEnhance.Brightness),
        ("contrast", ImageEnhance.Contrast),
    ]:
        if key in recipe:
            output = enhancer(output).enhance(recipe[key])
    if "blur" in recipe:
        output = output.filter(ImageFilter.GaussianBlur(recipe["blur"]))
    if "shadow" in recipe:
        gradient = Image.linear_gradient("L").rotate(90).resize(size)
        if recipe["shadow"] < 0:
            gradient = ImageOps.mirror(gradient)
        gradient = gradient.point(lambda v: 110 + int(v * 145 / 255))
        output = Image.composite(output, Image.new("RGB", size, "black"), gradient)
    if "tint" in recipe:
        output = ImageChops.multiply(output, Image.new("RGB", size, tuple(recipe["tint"])))
    if recipe.get("row_tint"):
        color = Image.new("RGB", size, "white")
        draw = ImageDraw.Draw(color)
        for row in ref["appointments"][::2]:
            draw.polygon(
                [(p["x"], p["y"]) for p in transform(m, row["row_polygon"])], fill="#ecedcf"
            )
        output = ImageChops.multiply(output, color)
    if "noise" in recipe:
        seed = json.dumps(
            [AUGMENTATION_VERSION, ref["sources"][0].get("source_hash"), recipe], sort_keys=True
        )
        rng = random.Random(hashlib.sha256(seed.encode()).digest())
        noise = Image.frombytes("L", size, rng.randbytes(size[0] * size[1]))
        noise = noise.point(lambda value: 128 + round((value - 128) * recipe["noise"] / 128))
        output = ImageChops.add(output, noise.convert("RGB"), offset=-128)
    for area, _ in obstructions(recipe, size):
        # Use the same half-open rectangle for pixels and label intersections.
        ImageDraw.Draw(output).rectangle((area[0], area[1], area[2] - 1, area[3] - 1), fill="white")
    return output, variant_labels(ref, recipe)[0], m


def variant_labels(ref, recipe):
    source = ref["sources"][0]
    m, size = matrix(recipe, source["width"], source["height"])
    lines = []
    for line in ref["lines"]:
        p, state = visibility(line["polygon"], source, recipe, m, size, line["state"])
        edges = [math.hypot(a["x"] - b["x"], a["y"] - b["y"]) for a, b in zip(p[-1:] + p[:-1], p)]
        if state == "legible" and min(edges) < 6:
            state = "illegible"
        lines.append(
            {
                **line,
                "polygon": p,
                "visible_polygon": clip(p, size),
                "source_state": line["state"],
                "state": state,
                "text": line["text"] if state == "legible" else "",
            }
        )
    return lines, m, size


def field_label(assessment, field_lines, source, recipe, m, size):
    polygon, state = visibility(assessment["polygon"], source, recipe, m, size, assessment["state"])
    if state == assessment["state"] and any(line["state"] != "legible" for line in field_lines):
        state = next(line["state"] for line in field_lines if line["state"] != "legible")
    return {
        "state": state,
        "source_state": assessment["state"],
        "polygon": polygon,
        "visible_polygon": clip(polygon, size),
        "frame": "variant",
    }

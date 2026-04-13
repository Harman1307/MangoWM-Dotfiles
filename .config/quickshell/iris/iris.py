import sys
import json
import math
import argparse
import subprocess
import re


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--wallpaper", required=True)
    p.add_argument("--dark",  type=int, default=1)
    p.add_argument("--glass", type=int, default=0)
    p.add_argument("--debug", action="store_true")
    return p.parse_args()


def extract_colors(wallpaper_path):
    resolved = subprocess.run(
        ["readlink", "-f", wallpaper_path],
        capture_output=True, text=True
    ).stdout.strip()

    if not resolved:
        resolved = wallpaper_path

    result = subprocess.run([
        "magick",
        resolved + "[0]",
        "-resize", "200x200!",
        "-colors", "16",
        "-depth", "8",
        "-format", "%c",
        "histogram:info:"
    ], capture_output=True, text=True)

    return result.stdout


def parse_histogram(raw):
    lines    = raw.strip().split("\n")
    clusters = []

    for line in lines:
        count_match = re.match(r"\s*(\d+):", line)
        hex_match   = re.search(r"#([0-9A-Fa-f]{6})", line)
        if not count_match or not hex_match:
            continue
        count   = int(count_match.group(1))
        h, s, l = hex_to_hsl(hex_match.group(1))
        clusters.append({
            "count": count,
            "h": h, "s": s, "l": l,
            "hex": "#" + hex_match.group(1).lower()
        })

    clusters.sort(key=lambda c: c["count"], reverse=True)
    return clusters


def hex_to_hsl(hex_str):
    r = int(hex_str[0:2], 16) / 255
    g = int(hex_str[2:4], 16) / 255
    b = int(hex_str[4:6], 16) / 255

    mx = max(r, g, b)
    mn = min(r, g, b)
    l  = (mx + mn) / 2

    if mx == mn:
        return 0.0, 0.0, l

    d = mx - mn
    s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)

    if mx == r:
        h = ((g - b) / d + (6 if g < b else 0)) / 6
    elif mx == g:
        h = ((b - r) / d + 2) / 6
    else:
        h = ((r - g) / d + 4) / 6

    return h * 360, s, l


def hsl_to_hex(h, s, l):
    h = h / 360

    if s == 0:
        v  = int(round(l * 255))
        hx = format(v, "02x")
        return "#" + hx + hx + hx

    def hue2rgb(p, q, t):
        if t < 0: t += 1
        if t > 1: t -= 1
        if t < 1/6: return p + (q - p) * 6 * t
        if t < 1/2: return q
        if t < 2/3: return p + (q - p) * (2/3 - t) * 6
        return p

    q = l * (1 + s) if l < 0.5 else l + s - l * s
    p = 2 * l - q

    r = hue2rgb(p, q, h + 1/3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1/3)

    rh = format(int(round(r * 255)), "02x")
    gh = format(int(round(g * 255)), "02x")
    bh = format(int(round(b * 255)), "02x")

    return "#" + rh + gh + bh


def relative_luminance(hex_str):
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16) / 255
    g = int(hex_str[2:4], 16) / 255
    b = int(hex_str[4:6], 16) / 255

    def linearize(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)


def contrast_ratio(hex1, hex2):
    l1      = relative_luminance(hex1)
    l2      = relative_luminance(hex2)
    lighter = max(l1, l2)
    darker  = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def hue_distance(h1, h2):
    d = abs(h1 - h2)
    if d > 180:
        d = 360 - d
    return d


def push_lightness(h, s, l, target_contrast, against_hex, go_darker):
    step = -0.01 if go_darker else 0.01
    for _ in range(100):
        candidate = hsl_to_hex(h, s, l)
        if contrast_ratio(candidate, against_hex) >= target_contrast:
            return candidate
        l = max(0.0, min(1.0, l + step))
    return hsl_to_hex(h, s, l)


def weighted_avg_lightness(clusters):
    total = sum(c["count"] for c in clusters)
    if total == 0:
        return 0.5
    return sum(c["l"] * c["count"] for c in clusters) / total


def is_monochrome(clusters):
    total   = sum(c["count"] for c in clusters)
    avg_sat = sum(c["s"] * c["count"] for c in clusters) / total
    return avg_sat < 0.08


def pick_bg(clusters, dark):
    sorted_by_l = sorted(clusters, key=lambda c: c["l"])

    if dark:
        for c in sorted_by_l:
            if c["l"] < 0.25 and c["s"] > 0.02:
                return c
        return sorted_by_l[0]
    else:
        for c in reversed(sorted_by_l):
            if c["l"] > 0.75 and c["s"] > 0.02:
                return c
        return sorted_by_l[-1]


def pick_accent(clusters, bg_hex, dark):
    best       = None
    best_score = -1

    for c in clusters:
        if c["s"] < 0.15:
            continue

        if contrast_ratio(c["hex"], bg_hex) < 1.5:
            continue

        vibrancy = c["s"] * (1 - abs(2 * c["l"] - 1))

        if vibrancy > best_score:
            best_score = vibrancy
            best       = c

    if best is None:
        for c in clusters:
            if contrast_ratio(c["hex"], bg_hex) >= 1.5:
                best = c
                break

    if best is None:
        best = clusters[0]

    return best


def fix_bg(c, dark, glass):
    h, s, l = c["h"], c["s"], c["l"]

    if dark:
        l = min(l, 0.20)
        l = max(l, 0.07)
        if glass:
            l = min(l, 0.15)
            l = max(l, 0.05)
    else:
        l = max(l, 0.82)
        l = min(l, 0.97)
        if glass:
            l = max(l, 0.88)
            l = min(l, 0.98)

    s = min(s, 0.30)
    s = max(s, 0.03)

    return hsl_to_hex(h, s, l), h, s, l


def fix_accent(c, bg_hex, dark):
    h, s, l = c["h"], c["s"], c["l"]

    target_l = 0.68 if dark else 0.38
    l        = target_l
    s        = max(s, 0.40)
    s        = min(s, 0.90)

    candidate = hsl_to_hex(h, s, l)

    if contrast_ratio(candidate, bg_hex) < 3.0:
        candidate = push_lightness(h, s, l, 3.0, bg_hex, True)

    return candidate, h, s


def fix_fg(bg_h, bg_s, bg_hex, dark):
    fg_l = 0.93 if dark else 0.10
    fg_s = min(bg_s * 0.6, 0.12)

    candidate = hsl_to_hex(bg_h, fg_s, fg_l)

    if contrast_ratio(candidate, bg_hex) < 4.5:
        candidate = push_lightness(bg_h, fg_s, fg_l, 4.5, bg_hex, dark)

    return candidate


def fix_dim(bg_h, bg_s, bg_hex, dark):
    dim_l = 0.48 if dark else 0.52
    dim_s = min(bg_s * 0.8, 0.14)

    candidate = hsl_to_hex(bg_h, dim_s, dim_l)

    if contrast_ratio(candidate, bg_hex) < 2.0:
        candidate = push_lightness(bg_h, dim_s, dim_l, 2.0, bg_hex, dark)

    return candidate


def fix_surface(bg_h, bg_s, bg_l, dark, glass):
    if dark:
        surface_l = min(bg_l + 0.05, 0.28)
    else:
        surface_l = max(bg_l - 0.05, 0.72)

    surface_s = min(bg_s * 1.1, 0.25)
    return hsl_to_hex(bg_h, surface_s, surface_l)


def semantic_color(target_h, accent_h, pull, s, l, bg_hex, dark):
    diff = accent_h - target_h
    if diff > 180:  diff -= 360
    if diff < -180: diff += 360

    drift = max(-20.0, min(20.0, diff * pull))
    h     = target_h + drift
    if h < 0:   h += 360
    if h > 360: h -= 360

    candidate = hsl_to_hex(h, s, l)

    if contrast_ratio(candidate, bg_hex) < 2.5:
        candidate = push_lightness(h, s, l, 2.5, bg_hex, True)

    return candidate


def build_monochrome(clusters, dark, glass, tone_l):
    bg_c                     = pick_bg(clusters, dark)
    bg_hex, bg_h, bg_s, bg_l = fix_bg(bg_c, dark, glass)

    fg_hex      = fix_fg(bg_h, bg_s, bg_hex, dark)
    dim_hex     = fix_dim(bg_h, bg_s, bg_hex, dark)
    surface_hex = fix_surface(bg_h, bg_s, bg_l, dark, glass)

    accent_l   = 0.65 if dark else 0.35
    accent_hex = hsl_to_hex(bg_h, 0.18, accent_l)

    if contrast_ratio(accent_hex, bg_hex) < 3.0:
        accent_hex = push_lightness(bg_h, 0.18, accent_l, 3.0, bg_hex, True)

    sem_s = 0.30
    sem_l = 0.68 if dark else 0.38

    return {
        "bg":      bg_hex,
        "surface": surface_hex,
        "fg":      fg_hex,
        "dim":     dim_hex,
        "accent":  accent_hex,
        "red":     semantic_color(5,   bg_h, 0.05, sem_s,        sem_l,        bg_hex, dark),
        "green":   semantic_color(130, bg_h, 0.05, sem_s,        sem_l,        bg_hex, dark),
        "yellow":  semantic_color(52,  bg_h, 0.05, sem_s + 0.05, sem_l + 0.02, bg_hex, dark),
        "mode":    "monochrome",
        "tone_l":  round(tone_l, 3)
    }


def build_palette(clusters, dark, glass, tone_l, mode):
    bg_c                     = pick_bg(clusters, dark)
    bg_hex, bg_h, bg_s, bg_l = fix_bg(bg_c, dark, glass)

    accent_c                       = pick_accent(clusters, bg_hex, dark)
    accent_hex, accent_h, accent_s = fix_accent(accent_c, bg_hex, dark)

    fg_hex      = fix_fg(bg_h, bg_s, bg_hex, dark)
    dim_hex     = fix_dim(bg_h, bg_s, bg_hex, dark)
    surface_hex = fix_surface(bg_h, bg_s, bg_l, dark, glass)

    sem_s = 0.65 if dark else 0.58
    sem_l = 0.70 if dark else 0.38

    return {
        "bg":      bg_hex,
        "surface": surface_hex,
        "fg":      fg_hex,
        "dim":     dim_hex,
        "accent":  accent_hex,
        "red":     semantic_color(5,   accent_h, 0.25, sem_s,        sem_l,        bg_hex, dark),
        "green":   semantic_color(130, accent_h, 0.25, sem_s - 0.05, sem_l - 0.02, bg_hex, dark),
        "yellow":  semantic_color(52,  accent_h, 0.20, sem_s + 0.05, sem_l + 0.02, bg_hex, dark),
        "mode":    mode,
        "tone_l":  round(tone_l, 3)
    }


def main():
    args     = parse_args()
    dark     = args.dark  == 1
    glass    = args.glass == 1
    raw      = extract_colors(args.wallpaper)
    clusters = parse_histogram(raw)

    if not clusters:
        print(json.dumps({
            "bg":      "#11111b",
            "surface": "#1e1e2e",
            "fg":      "#cdd6f4",
            "dim":     "#6c7086",
            "accent":  "#89b4fa",
            "red":     "#f38ba8",
            "green":   "#a6e3a1",
            "yellow":  "#f9e2af",
            "mode":    "fallback",
            "tone_l":  0.1
        }))
        return

    tone_l = weighted_avg_lightness(clusters)

    if args.debug:
        total   = sum(c["count"] for c in clusters)
        avg_sat = sum(c["s"] * c["count"] for c in clusters) / total
        bg_c    = pick_bg(clusters, dark)
        bg_hex_d, bg_h_d, bg_s_d, bg_l_d = fix_bg(bg_c, dark, glass)
        acc_c   = pick_accent(clusters, bg_hex_d, dark)

        print(f"tone_l:   {tone_l:.3f}",  file=sys.stderr)
        print(f"avg_sat:  {avg_sat:.3f}", file=sys.stderr)
        print(f"mono:     {is_monochrome(clusters)}", file=sys.stderr)
        print(f"bg pick:  h={bg_c['h']:.1f} s={bg_c['s']:.3f} l={bg_c['l']:.3f} {bg_c['hex']}", file=sys.stderr)
        print(f"bg fixed: {bg_hex_d}", file=sys.stderr)
        print(f"accent:   h={acc_c['h']:.1f} s={acc_c['s']:.3f} l={acc_c['l']:.3f} {acc_c['hex']}", file=sys.stderr)
        print("all clusters:", file=sys.stderr)
        for c in clusters:
            print(f"  {c['hex']}  h={c['h']:.1f} s={c['s']:.3f} l={c['l']:.3f} count={c['count']}", file=sys.stderr)

    if is_monochrome(clusters):
        palette = build_monochrome(clusters, dark, glass, tone_l)
    else:
        vibrant_count = sum(
            1 for c in clusters
            if c["s"] > 0.35 and 0.15 < c["l"] < 0.85
        )
        mode    = "vibrant" if vibrant_count >= 2 else "muted"
        palette = build_palette(clusters, dark, glass, tone_l, mode)

    print(json.dumps(palette))


main()
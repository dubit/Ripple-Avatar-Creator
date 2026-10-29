"""Build assets/world/clouds.png: the "Clouds" floor pattern.

Seamless fractal Perlin noise, white on transparent (the noise is the alpha),
tinted by the pattern colour in-game. Tileable because every octave's
gradient lattice wraps (its period divides the image size).

Run from the repo root:  python tools/build_clouds.py
"""

import numpy as np
from PIL import Image

SIZE = 512
BASE_CELLS = 4  # lattice cells across the tile for the first octave
OCTAVES = 4
PERSISTENCE = 0.5  # each octave's amplitude relative to the last
SEED = 7
# Noise (0..1) mapped to alpha: below LOW is clear, above HIGH is solid.
LOW, HIGH = 0.3, 0.85


def perlin(size, cells, rng):
    """Periodic 2D Perlin noise, roughly -1..1, wrapping every `size` pixels."""
    angles = rng.uniform(0, 2 * np.pi, (cells, cells))
    grads = np.stack([np.cos(angles), np.sin(angles)], axis=-1)
    coords = np.arange(size) * cells / size
    x, y = np.meshgrid(coords, coords)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells

    def dot(gx, gy, dx, dy):
        g = grads[gy, gx]
        return g[..., 0] * dx + g[..., 1] * dy

    def fade(t):
        return t * t * t * (t * (t * 6 - 15) + 10)

    u, v = fade(fx), fade(fy)
    n00 = dot(x0, y0, fx, fy)
    n10 = dot(x1, y0, fx - 1, fy)
    n01 = dot(x0, y1, fx, fy - 1)
    n11 = dot(x1, y1, fx - 1, fy - 1)
    top = n00 + u * (n10 - n00)
    bottom = n01 + u * (n11 - n01)
    return (top + v * (bottom - top)) * np.sqrt(2)


def main():
    rng = np.random.default_rng(SEED)
    total = np.zeros((SIZE, SIZE))
    amplitude, norm = 1.0, 0.0
    for octave in range(OCTAVES):
        total += amplitude * perlin(SIZE, BASE_CELLS * 2**octave, rng)
        norm += amplitude
        amplitude *= PERSISTENCE
    noise = (total / norm + 1) / 2  # ~0..1
    noise = (noise - noise.min()) / (noise.max() - noise.min())
    t = np.clip((noise - LOW) / (HIGH - LOW), 0, 1)
    alpha = t * t * (3 - 2 * t)  # smoothstep
    rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(alpha * 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save('assets/world/clouds.png')
    print('assets/world/clouds.png', f'{(alpha > 0.5).mean():.0%} covered')


if __name__ == '__main__':
    main()

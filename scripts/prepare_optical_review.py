"""Prepare small image pairs for review without assigning flood labels."""
from pathlib import Path
import os
import json
import hashlib
import numpy as np
import pandas as pd
import rasterio
from rasterio.io import MemoryFile

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault('MPLCONFIGDIR', str(ROOT / 'data/cache/matplotlib'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def prepare_review():
    raw = ROOT / 'data/raw/optical_pilot'
    out = ROOT / 'data/processed/optical_review'
    figures = ROOT / 'data/figures/optical_review'
    out.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((raw / 'crop_manifest.json').read_text())
    arrays = {}
    grid = None
    for date in ('20240422', '20240502'):
        arrays[date] = {}
        for band in ('B04', 'B03', 'B02', 'SCL'):
            entry = next(e for e in manifest['files'] if date in e['scene_id'] and e['band'] == band)
            content = (raw / entry['file']).read_bytes()
            assert hashlib.sha256(content).hexdigest() == entry['sha256']
            with MemoryFile(content) as memory, memory.open() as src:
                current = (src.crs, src.transform, src.shape)
                if grid is None:
                    grid = current
                assert current == grid, 'Image grids differ'
                arrays[date][band] = src.read(1)
        rgb = np.stack([arrays[date][b] for b in ('B04', 'B03', 'B02')], axis=-1)
        arrays[date]['rgb'] = np.clip((rgb.astype(float) - 1000) / 3000, 0, 1) ** (1 / 1.8)
        arrays[date]['clear'] = np.isin(arrays[date]['SCL'], [4, 5, 6]) & (rgb > 0).all(axis=-1)
    before, after = arrays.values()
    shared = before['clear'] & after['clear']
    rows = []
    for r in range(0, 500, 50):
        for c in range(0, 500, 50):
            sl = np.s_[r:r+50, c:c+50]
            left, top = grid[1] * (c, r)
            right, bottom = grid[1] * (c+50, r+50)
            rows.append(dict(sample_id=f'patch_r{r:03d}_c{c:03d}', row=r, col=c,
                             west=left, south=bottom, east=right, north=top,
                             shared_clear_fraction=float(shared[sl].mean()),
                             both_dates_scl_water_fraction=float(((before['SCL'][sl] == 6) & (after['SCL'][sl] == 6)).mean()),
                             sector=f'{r//250}_{c//125}'))
    inventory = pd.DataFrame(rows)
    # Pick one clear sample in each of eight parts of the square.
    eligible = inventory[inventory.shared_clear_fraction >= .9]
    selected = eligible.sort_values(['shared_clear_fraction', 'sample_id'], ascending=[False, True]).groupby('sector', sort=True).head(1).copy()
    selected = selected.sort_values('sample_id')
    assert len(selected) > 0
    inventory['selected'] = inventory.sample_id.isin(selected.sample_id)
    inventory.to_csv(out / 'patch_inventory.csv', index=False)
    selected['before_date'] = '2024-04-22'
    selected['after_date'] = '2024-05-02'
    selected['crs'] = str(grid[0])
    selected['assessment'] = 'pending_review'
    selected['reviewer'] = ''
    selected['notes'] = ''
    selected['flood_label'] = pd.NA
    review_path = out / 'sample_review.csv'
    # Keep any notes already entered by a reviewer.
    if review_path.exists():
        old = pd.read_csv(review_path).set_index('sample_id')
        for idx, row in selected.iterrows():
            if row.sample_id in old.index:
                for field in ('assessment', 'reviewer', 'notes', 'flood_label'):
                    selected.at[idx, field] = old.at[row.sample_id, field]
    selected.to_csv(review_path, index=False)
    for page, start in enumerate(range(0, len(selected), 4), 1):
        batch = selected.iloc[start:start+4]
        fig, axes = plt.subplots(len(batch), 3, figsize=(10, 3 * len(batch)), squeeze=False)
        for axes_row, (_, row) in zip(axes, batch.iterrows()):
            r, c = int(row.row), int(row.col)
            sl = np.s_[r:r+50, c:c+50]
            for ax, img, title in zip(axes_row, [before['rgb'][sl], after['rgb'][sl], shared[sl]],
                                      ['22 April', '2 May', 'Clear on both dates (white)']):
                ax.imshow(img, interpolation='nearest', cmap='gray', vmin=0, vmax=1)
                ax.set_title(title, fontsize=9)
                ax.set_xticks([])
                ax.set_yticks([])
            axes_row[0].set_ylabel(row.sample_id + '\n500 m square', fontsize=8)
        fig.suptitle('Visual review only: colour changes do not establish flooding', fontsize=11)
        fig.tight_layout()
        fig.savefig(figures / f'image_pairs_{page}.png', dpi=140)
        plt.close(fig)
    result = {'patches_checked': len(inventory), 'eligible_patches': len(eligible),
              'selected_patches': len(selected), 'minimum_shared_clear_fraction': float(selected.shared_clear_fraction.min()),
              'selection': 'Highest shared clear coverage in each of eight spatial sectors; ties use sample ID.',
              'limits': 'Purposive pilot sample. April 22 is not confirmed dry. May 2 is after the May 1 reference. No automatic flood labels.'}
    (out / 'review_metadata.json').write_text(json.dumps(result, indent=2) + '\n')
    return result

if __name__ == '__main__':
    print(json.dumps(prepare_review(), indent=2))

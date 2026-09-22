#!/usr/bin/env python3
"""Turn a folder of Meshy monster downloads into game-sized
assets/beasts/<bestiary-id>.glb.

    python3 tools/import_beasts.py                  # everything in assets/NewlyDownloadedModels
    python3 tools/import_beasts.py Ogre Wolf_alt_1  # just these (basename, no .glb)
    SRC=~/Downloads/batch3 python3 tools/import_beasts.py
    python3 tools/import_beasts.py --check          # name the files, convert nothing

ANY MONSTER, not just beasts. The name is historical -- the first batch was 81
animals -- but nothing in here is beast-specific and neither is the lookup it
feeds: scenes/figures3d.gd asks for assets/beasts/<bestiary id>.glb for EVERY
foe before it falls back to the faction rig, so an ogre, a wyvern or a
gelatinous cube named after its bestiary id is drawn the moment its file
lands. tests/test_figure_models.gd prints which factions are still without one.

The downloads are photogrammetry-shaped: up to 1.4M triangles and 3-4 PBR
textures at 2048-8192 square apiece, 1.9 GB for 81 files. A figure is ~200px
tall on the board and the compat renderer draws one albedo, so each becomes
~20k triangles (gltfpack -sa, meshoptimizer's simplifier) with only the
base-colour texture, resampled to 1024 by tools/shrink_glb.py. The source
folder is gitignored; only the output is committed.

Name -> bestiary id is mechanical (CamelCase -> kebab, "_alt_N" dropped), with
known download typos spelled out in FIXUPS. Where a name has several alts the
first wins; the rest are skipped. A name that does NOT resolve to an id in
data/bestiary.json is REFUSED rather than written: the id is the whole of how
the game finds the file, so "DragonRed.glb" -> dragon-red.glb would convert
cleanly, commit cleanly, and never be drawn by anything. Pass --force to write
it anyway (an id a content pack adds is a real case).

Godot extracts the embedded texture beside the .glb on import and writes its
.import with compress/mode=0 -- see shrink_glb.py's second warning; run the
sed + `godot --headless --import` it names afterwards.
"""
import glob, json, os, re, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(__file__))
from shrink_glb import read_glb, write_glb, shrink

SRC = os.environ.get('SRC', 'assets/NewlyDownloadedModels')
DST = os.environ.get('DST', 'assets/beasts')
BESTIARY = 'data/bestiary.json'
TRIS, TEX = 20000, 1024
# The 2026-09-22 batch came down with the words run together; ogre2 is a second
# ogre and orcarcher stands in for the one orc the bestiary has.
FIXUPS = {'pleisosaurus': 'plesiosaurus', 'deathdog': 'death-dog',
          'frostgiant': 'frost-giant', 'gnollarcher': 'gnoll-archer',
          'gnollwarrior': 'gnoll', 'hillgiant': 'hill-giant',
          'hillgiantarcher': 'hill-giant-archer', 'ogre1': 'ogre', 'ogre2': 'ogre',
          'orcarcher': 'orc', 'phasespider': 'phase-spider',
          'rustmonster': 'rust-monster', 'winterwolf': 'winter-wolf'}

def bestiary_id(name):
    s = re.sub(r'_alt_\d+$', '', name)
    s = re.sub(r'(?<=[a-z])(?=[A-Z])', '-', s).lower().replace('_', '-')
    return FIXUPS.get(s, s)

def known_ids():
    """Every id in the bestiary. The file name IS the lookup key (figures3d.gd's
    BEAST_DIR), so this is what decides whether a converted model is reachable."""
    with open(BESTIARY) as f:
        return {m['id'] for m in json.load(f)}

def tri_count(j):
    return sum(j['accessors'][p['indices']]['count'] // 3 if 'indices' in p
               else j['accessors'][p['attributes']['POSITION']]['count'] // 3
               for m in j.get('meshes', []) for p in m.get('primitives', []))

def albedo_only(j):
    """Drop every texture slot but baseColor, then the images/textures/bufferViews
    nothing references any more. shrink() rebuilds the binary chunk from the
    bufferViews list, so a view removed here takes its bytes with it."""
    for m in j.get('materials', []):
        for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
            m.pop(k, None)
        m.get('pbrMetallicRoughness', {}).pop('metallicRoughnessTexture', None)
        m.pop('emissiveFactor', None)
    used_tex = sorted({m['pbrMetallicRoughness']['baseColorTexture']['index']
                       for m in j.get('materials', []) if 'baseColorTexture' in m.get('pbrMetallicRoughness', {})})
    assert used_tex, "no baseColorTexture"
    tex_map = {old: new for new, old in enumerate(used_tex)}
    j['textures'] = [j['textures'][i] for i in used_tex]
    for m in j.get('materials', []):
        bct = m.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if bct:
            bct['index'] = tex_map[bct['index']]
    used_img = sorted({t['source'] for t in j['textures']})
    img_map = {old: new for new, old in enumerate(used_img)}
    j['images'] = [j['images'][i] for i in used_img]
    for t in j['textures']:
        t['source'] = img_map[t['source']]
    used_bv = {a['bufferView'] for a in j.get('accessors', []) if 'bufferView' in a}
    used_bv |= {i['bufferView'] for i in j['images']}
    keep = sorted(used_bv)
    bv_map = {old: new for new, old in enumerate(keep)}
    j['bufferViews'] = [j['bufferViews'][i] for i in keep]
    for a in j.get('accessors', []):
        if 'bufferView' in a:
            a['bufferView'] = bv_map[a['bufferView']]
        for k in ('indices', 'values'):
            if 'sparse' in a:
                a['sparse'][k]['bufferView'] = bv_map[a['sparse'][k]['bufferView']]
    for i in j['images']:
        i['bufferView'] = bv_map[i['bufferView']]
        i['name'] = 'albedo'          # Godot names the extracted file after this

def convert(src, dst):
    j, b = read_glb(src)
    tris = tri_count(j)
    work = src
    if tris > TRIS:
        work = tempfile.mktemp(suffix='.glb')
        subprocess.run(['npx', '--yes', 'gltfpack', '-i', src, '-o', work, '-noq',
                        '-si', f'{TRIS / tris:.4f}', '-sa'], check=True, capture_output=True)
        j, b = read_glb(work)
    albedo_only(j)
    write_glb(dst, j, b)
    if work != src:
        os.remove(work)
    shrink(dst, max_dim=TEX)
    return tris, tri_count(j)

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = {a for a in sys.argv[1:] if a.startswith('--')}
    check_only, force = '--check' in flags, '--force' in flags
    ids = known_ids()
    names = args or sorted(os.path.basename(p)[:-4] for p in glob.glob(f'{SRC}/*.glb'))
    if not names:
        sys.exit(f"nothing to do: no .glb in {SRC} (set SRC=... for a batch elsewhere)")
    if not check_only:
        os.makedirs(DST, exist_ok=True)
    done, refused = set(), 0
    for n in names:
        bid = bestiary_id(n)
        if bid in done:
            print(f"  {n}: skipped, {bid} already taken")
            continue
        if bid not in ids and not force:
            refused += 1
            print(f"  {n}: REFUSED, '{bid}' is not an id in {BESTIARY} -- "
                  f"nothing would ever draw it. Rename the download, add it to "
                  f"FIXUPS, or pass --force.")
            continue
        j, _ = read_glb(f'{SRC}/{n}.glb')
        if not any('baseColorTexture' in m.get('pbrMetallicRoughness', {}) for m in j.get('materials', [])):
            print(f"  {n}: skipped, no albedo texture (an untextured download draws as a white blob)")
            continue
        done.add(bid)
        if check_only:
            print(f"  {n} -> {bid}.glb")
            continue
        before, after = convert(f'{SRC}/{n}.glb', f'{DST}/{bid}.glb')
        print(f"  {n} -> {bid}.glb  {before} -> {after} tris  {os.path.getsize(f'{DST}/{bid}.glb') / 1e6:.1f} MB")
    print(f"\n{len(done)} model{'' if len(done) == 1 else 's'}"
          f"{' named' if check_only else ' written'}, {refused} refused.")
    if refused:
        sys.exit(1)

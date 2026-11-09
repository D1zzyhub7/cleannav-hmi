#!/usr/bin/env python3
"""Offline display artifacts only. Never emits a navigation map or reads a world.

Dependencies: OpenCV, NumPy, SciPy, Pillow, PyYAML. See REFERENCES.md.
Run: python3 tools/render_display_map.py --inputs inputs --output outputs
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
import yaml

CONNECTED = np.ones((3, 3), dtype=bool)
COLORS = {'unknown': (233, 236, 239), 'free': (252, 253, 254),
          'occupied': (53, 63, 73)}
PARAMS = {
    'conservative': {'radius_cells': 1, 'geometry': False},
    'balanced': {'radius_cells': 1, 'geometry': True},
    'aggressive': {'radius_cells': 3, 'geometry': True},
}


def classify(image, meta):
    probability = image.astype(float) / 255
    if not meta['negate']:
        probability = 1 - probability
    occupied = probability > meta['occupied_thresh']
    free = probability < meta['free_thresh']
    return occupied, free, ~(occupied | free)


def components(mask):
    labels, count = ndi.label(mask, CONNECTED)
    return labels, np.bincount(labels.ravel(), minlength=count + 1)


def border_connected(mask):
    seed = np.zeros_like(mask)
    seed[[0, -1], :] = mask[[0, -1], :]
    seed[:, [0, -1]] = mask[:, [0, -1]]
    return ndi.binary_propagation(seed, mask=mask, structure=CONNECTED)


def contours(mask, mode=cv2.RETR_TREE):
    return cv2.findContours(mask.astype(np.uint8), mode, cv2.CHAIN_APPROX_NONE)


def boundary(mask):
    return mask & ~ndi.binary_erosion(mask, structure=CONNECTED, border_value=0)


def distance(mask):
    return ndi.distance_transform_edt(~mask)


def clean_small(occupied, free, unknown):
    """Only small OUTSIDE components, never arbitrary small interior obstacles."""
    flabel, sizes = components(free)
    main = flabel == (1 + sizes[1:].argmax())
    outside = border_connected(unknown)
    main_distance = distance(main)
    near_main = ndi.binary_dilation(main, iterations=2)
    olab, osizes = components(occupied)
    removed = np.zeros_like(occupied)
    records = []
    for label in range(1, len(osizes)):
        part = olab == label
        if osizes[label] <= 2 and not np.any(part & near_main) and np.all(main_distance[part] > 2):
            # Every pixel must border exterior unknown; wall-adjacent fragments stay.
            if np.all(ndi.binary_dilation(outside)[part]):
                removed |= part
                records.append({'kind': 'external_occupied', 'pixels': int(osizes[label]),
                                'bbox_xywh': bbox(part)})
    removed_free = np.zeros_like(free)
    for label in range(1, len(sizes)):
        part = flabel == label
        if sizes[label] <= 4 and np.all(main_distance[part] > 2) and np.any(ndi.binary_dilation(part) & outside):
            removed_free |= part
            records.append({'kind': 'external_free_fragment', 'pixels': int(sizes[label]),
                            'bbox_xywh': bbox(part)})
    return occupied & ~removed, free & ~removed_free, main, outside, records


def bbox(mask):
    yy, xx = np.where(mask)
    return [int(xx.min()), int(yy.min()), int(xx.max()-xx.min()+1), int(yy.max()-yy.min()+1)]


def close_small(mask, radius):
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2*radius+1, 2*radius+1))
    closed = cv2.morphologyEx(mask.astype('uint8'), cv2.MORPH_CLOSE, kernel,
                             borderType=cv2.BORDER_CONSTANT, borderValue=0).astype(bool)
    # Elliptic discrete kernels include some diagonal offsets > radius.
    # Explicitly cap addition distance and preserve all original pixels.
    return mask | (closed & (distance(mask) <= radius))


def fill_small_holes(mask, threshold):
    holes = ndi.binary_fill_holes(mask) & ~mask
    labels, sizes = components(holes)
    return mask | (np.isin(labels, np.flatnonzero((sizes <= threshold) & (np.arange(len(sizes)) > 0))))


def circle_fit(contour):
    points = contour[:, 0, :].astype(float)
    # Center the coordinates before least squares to avoid a poorly conditioned fit.
    mean = points.mean(axis=0)
    points -= mean
    fit = np.linalg.lstsq(np.c_[2*points, np.ones(len(points))], (points**2).sum(axis=1), rcond=None)[0]
    center = fit[:2] + mean
    radius = math.sqrt(max(0, fit[2] + (fit[:2]**2).sum()))
    rms = np.sqrt(np.mean((np.linalg.norm(points-fit[:2], axis=1)-radius)**2))
    return center, radius, float(rms)


def shape_mask(shape, size, scale=1):
    """Analytic geometry at pixel centers. Coordinates are native image indices."""
    h, w = size
    yy, xx = np.mgrid[:h*scale, :w*scale].astype(float)
    xx = (xx + .5)/scale - .5
    yy = (yy + .5)/scale - .5
    if shape['kind'] == 'circle':
        cx, cy = shape['center']
        rr = (xx-cx)**2 + (yy-cy)**2
        return (rr <= shape['radius']**2) & (rr >= shape['inner_radius']**2)
    points = np.array(shape['points'], dtype=float)
    # Convex line bands/rectangles: sample exact pixel centers instead of rounding
    # polygon vertices (rounding widens a one-cell wall by a whole extra cell).
    signs = []
    for a, b in zip(points, np.roll(points, -1, axis=0)):
        signs.append((b[0]-a[0])*(yy-a[1]) - (b[1]-a[1])*(xx-a[0]))
    signs = np.stack(signs)
    return np.all(signs >= -1e-9, axis=0) | np.all(signs <= 1e-9, axis=0)


def regularize(mask, original, resolution, aggressive=False):
    result = mask.copy()
    accepted, decisions = [], []
    labels, sizes = components(mask)
    yy, xx = np.mgrid[:mask.shape[0], :mask.shape[1]]
    to_original = distance(original)
    for label in range(1, len(sizes)):
        part = labels == label
        if sizes[label] < 15:
            continue
        cnt = max(contours(part, cv2.RETR_EXTERNAL)[0], key=cv2.contourArea)
        x, y, w, h = cv2.boundingRect(cnt)
        area = cv2.contourArea(cnt)
        perimeter = cv2.arcLength(cnt, True)
        circularity = 4*math.pi*area/perimeter**2 if perimeter else 0
        rect = cv2.minAreaRect(cnt)
        rw, rh = rect[1]
        rectangularity = area / (rw*rh) if rw*rh > 0 else 0
        decision = {'component': label, 'bbox_xywh': [x, y, w, h], 'pixels': int(sizes[label]),
                    'circularity': circularity, 'rectangularity': rectangularity,
                    'result': 'original contour retained'}
        shape = None
        if 0.20 <= min(w, h)*resolution <= 1.2 and max(w, h)/min(w, h) <= (1.7 if aggressive else 1.4):
            center, radius, rms = circle_fit(cnt)
            decision.update(circle_center=center.tolist(), circle_radius_m=radius*resolution,
                            circle_rms_m=rms*resolution)
            if circularity >= (.5 if aggressive else .7) and .15 <= radius*resolution <= .5 and rms <= radius*(.3 if aggressive else .18):
                # Keep a well-supported central hole: do not turn sparse rings into solid pillars.
                holes = ndi.binary_fill_holes(part) & ~part
                inner = math.sqrt(max(0, radius**2 - sizes[label]/math.pi)) if holes.sum() > 4 else 0
                if inner == 0 or np.linalg.norm(np.array(ndi.center_of_mass(holes))[::-1]-center) <= 1.5:
                    shape = {'kind': 'circle', 'center': center.tolist(), 'radius': float(radius), 'inner_radius': inner}
        if shape is None and min(rw, rh) > 0 and max(rw, rh)/min(rw, rh) >= 15 and max(rw, rh)*resolution >= 2:
            points = cnt[:, 0, :].astype(float)
            vx, vy, cx, cy = cv2.fitLine(cnt, cv2.DIST_L2, 0, .01, .01).ravel().astype(float)
            tangent = np.array([vx, vy]); normal = np.array([-vy, vx]); center = np.array([cx, cy])
            along, across = (points-center)@tangent, (points-center)@normal
            rms = float(np.sqrt(np.mean(across**2)))
            decision['line_rms_m'] = rms*resolution
            if rms <= (1.2 if aggressive else .75):
                thickness = max(1., min(3., sizes[label]/max(1, along.max()-along.min())))
                poly = [center+t*tangent+s*normal for t, s in [(along.min(), -thickness/2), (along.max(), -thickness/2), (along.max(), thickness/2), (along.min(), thickness/2)]]
                shape = {'kind': 'wall_line', 'points': np.array(poly).tolist()}
        if shape is None and min(rw, rh) >= 4 and rectangularity >= (.8 if aggressive else .92):
            shape = {'kind': 'rectangle', 'points': cv2.boxPoints(rect).tolist()}
        if shape is not None:
            candidate = shape_mask(shape, mask.shape)
            iou = (part & candidate).sum()/max(1, (part | candidate).sum())
            sym_distance = max(float(distance(part)[candidate].max(initial=0)), float(distance(candidate)[part].max(initial=0)))
            added_distance = float(to_original[candidate & ~original].max(initial=0))
            decision.update(proposed=shape['kind'], local_iou=float(iou), max_displacement_cells=sym_distance,
                            max_added_from_original_cells=added_distance)
            limit = 3 if aggressive else 2
            if iou >= (.35 if aggressive else .5) and sym_distance <= limit and added_distance <= limit:
                result[part] = False
                result |= candidate
                decision['result'] = 'accepted'
                shape['source_component'] = label
                shape['bbox_xywh'] = [x, y, w, h]
                accepted.append(shape)
        decisions.append(decision)
    return result, accepted, decisions


def metrics(mask, original, resolution):
    contours_, hierarchy = contours(mask)
    border = boundary(mask); original_border = boundary(original)
    distances = np.r_[distance(original_border)[border], distance(border)[original_border]]*resolution
    holes = ndi.binary_fill_holes(mask) & ~mask
    added, removed = mask & ~original, original & ~mask
    # 8-neighbor degree-one occupied pixels quantify unjoined stroke endpoints.
    neighbors = ndi.convolve(mask.astype(int), np.ones((3, 3), dtype=int), mode='constant') - mask
    return {'occupied_pixels': int(mask.sum()), 'occupied_area_m2': float(mask.sum()*resolution**2),
            'area_change_pct': float((mask.sum()/original.sum()-1)*100),
            'added_pixels': int(added.sum()), 'removed_pixels': int(removed.sum()),
            'perimeter_m': float(sum(cv2.arcLength(c, True) for c in contours_)*resolution),
            'perimeter_change_pct': float((sum(cv2.arcLength(c,True) for c in contours_)/sum(cv2.arcLength(c,True) for c in contours(original)[0])-1)*100),
            'components_8': len(components(mask)[1])-1, 'holes_8': len(components(holes)[1])-1,
            'open_stroke_endpoints_8': int((mask & (neighbors == 1)).sum()),
            'iou': float((mask & original).sum()/max(1, (mask | original).sum())),
            'boundary_hausdorff_m': float(distances.max(initial=0)),
            'boundary_distance_p95_m': float(np.percentile(distances, 95)),
            'max_added_distance_from_original_m': float(distance(original)[added].max(initial=0)*resolution)}


def render(mask, free, shapes, scale=4):
    """High resolution polygon/circle rendering, then Lanczos; no HMI markers."""
    h, w = mask.shape
    hi = np.zeros((h*scale, w*scale, 3), dtype='uint8')
    hi[:] = COLORS['unknown']
    hi[np.repeat(np.repeat(free, scale, axis=0), scale, axis=1)] = COLORS['free']
    occupied_hi = np.repeat(np.repeat(mask, scale, axis=0), scale, axis=1)
    # Fill polygon contours at 4x. This keeps irregular contours including holes.
    ct, hierarchy = contours(occupied_hi)
    polygon_hi = np.zeros_like(occupied_hi, dtype='uint8')
    cv2.drawContours(polygon_hi, ct, -1, 1, cv2.FILLED, hierarchy=hierarchy)
    occupied_hi = polygon_hi.astype(bool)
    # Analytic circles and line polygons retain subcell edges at 4x.
    for shape in shapes:
        local = shape_mask(shape, mask.shape)
        # Replace precisely the accepted native shape, preserving neighboring features.
        local_hi = np.repeat(np.repeat(local, scale, axis=0), scale, axis=1)
        occupied_hi[local_hi] = False
        occupied_hi |= shape_mask(shape, mask.shape, scale)
    hi[occupied_hi] = COLORS['occupied']
    return Image.fromarray(hi).resize((w, h), Image.LANCZOS)


def contour_json(mask):
    cs, hierarchy = contours(mask)
    return {'contours_xy': [c[:, 0, :].tolist() for c in cs],
            'hierarchy_next_previous_child_parent': hierarchy[0].tolist() if hierarchy is not None else []}


def save_mask(path, mask):
    Image.fromarray(mask.astype('uint8')*255).save(path)


def compose(images, labels, dest, columns=2):
    width, height = images[0].size
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 18)
    canvas = Image.new('RGB', (width*columns, (height+40)*math.ceil(len(images)/columns)), 'white')
    draw = ImageDraw.Draw(canvas)
    for i, (im, label) in enumerate(zip(images, labels)):
        x, y = (i % columns)*width, (i//columns)*(height+40)
        canvas.paste(im, (x, y+40)); draw.text((x+10,y+10), label, fill=(30,40,50),font=font)
    canvas.save(dest)


def run(inputs, out):
    out.mkdir(parents=True, exist_ok=True)
    image = np.asarray(Image.open(inputs/'map.pgm'))
    meta = yaml.safe_load((inputs/'map.yaml').read_text())
    resolution = meta['resolution']
    occupied, free, unknown = classify(image, meta)
    cleaned, free_clean, main, outside, noise = clean_small(occupied, free, unknown)
    for name, mask in [('occupied_original',occupied), ('free_original',free), ('unknown_original',unknown),
                       ('main_free',main), ('exterior_unknown',outside), ('interior_unknown',unknown & ~outside)]:
        save_mask(out/(name+'.png'), mask)
    original_features = {'outer_free_boundary': contour_json(main), 'walls': [],
                         'internal_obstacles': [], 'unclassified_fragments': []}
    labels, sizes = components(occupied)
    for label in range(1, len(sizes)):
        part = labels == label
        x,y,w,h = bbox(part)
        group = ('internal_obstacles' if 5<=w<=24 and 5<=h<=24 and sizes[label]>=15 else
                 'walls' if max(w,h)/min(w,h)>=8 and max(w,h)*resolution>=2 else 'unclassified_fragments')
        original_features[group].append({'component':label,'bbox_xywh':[x,y,w,h],**contour_json(part)})
    (out/'contours_original.json').write_text(json.dumps(original_features,indent=2))
    original_render = render(occupied, free, [])
    original_render.save(out/'map_original_palette.png')
    Image.fromarray(image).save(out/'map_original_pgm.png')
    result = {'metadata': {'width':image.shape[1], 'height':image.shape[0], 'resolution':resolution,
                          'origin':meta['origin'], 'scale':1, 'supersampling':4,
                          'source_pgm_sha256':hashlib.sha256((inputs/'map.pgm').read_bytes()).hexdigest()},
              'thresholds': {'occupied_gt':meta['occupied_thresh'], 'free_lt':meta['free_thresh'], 'negate':meta['negate']},
              'noise_removed': noise,
              'parameters': {'outside_occupied_max_pixels':2,'outside_free_max_pixels':4,'hole_max_pixels':4,
                             'corresponding_areas_m2':{'2_pixels':2*resolution**2,'4_pixels':4*resolution**2},
                             'balanced_circle_circularity_min':.7,'balanced_circle_radial_rms_fraction_max':.18,
                             'balanced_circle_radius_m':[.15,.5],'balanced_wall_aspect_min':15,
                             'balanced_line_rms_m_max':.75*resolution,'balanced_rectangle_rectangularity_min':.92,
                             'balanced_geometry_max_displacement_m':2*resolution},
              'variants': {'original': metrics(occupied,occupied,resolution)}}
    variants = {}
    for radius in [1,2,3]:
        closed = close_small(cleaned,radius)
        save_mask(out/f'closing_{radius}_mask.png',closed)
        render(closed,free_clean,[]).save(out/f'closing_{radius}_cells.png')
        result[f'closing_{radius}'] = {'radius_cells':radius,'radius_m':radius*resolution,
                                     'kernel_width_cells':2*radius+1, **metrics(closed,occupied,resolution)}
    for name, param in PARAMS.items():
        processed = fill_small_holes(close_small(cleaned,param['radius_cells']),4)
        shapes, decisions = [], []
        if param['geometry']:
            processed, shapes, decisions = regularize(processed,occupied,resolution,name=='aggressive')
        png = render(processed,free_clean,shapes)
        png.save(out/f'map_display_{name}.png')
        save_mask(out/f'occupied_{name}.png',processed)
        (out/f'geometry_{name}.json').write_text(json.dumps({'accepted':shapes,'decisions':decisions},indent=2))
        (out/f'contours_{name}.json').write_text(json.dumps(contour_json(processed)))
        variants[name] = processed
        result['variants'][name] = {'closing_radius_cells':param['radius_cells'],
                                   'circle_count':sum(s['kind']=='circle' for s in shapes),
                                   'wall_line_count':sum(s['kind']=='wall_line' for s in shapes),
                                   'rectangle_count':sum(s['kind']=='rectangle' for s in shapes),
                                   **metrics(processed,occupied,resolution)}
    (out/'map_display_recommended.png').write_bytes((out/'map_display_balanced.png').read_bytes())
    # Record the actual original-component joins, rather than claiming every gap closed.
    old_labels,_=components(occupied)
    joined,join_sizes=components(close_small(cleaned,1))
    repairs=[]
    for label in range(1,len(join_sizes)):
        part=joined==label
        ids=np.unique(old_labels[part]);ids=ids[ids>0]
        if len(ids)>1:
            additions=part & ~occupied
            repairs.append({'merged_original_component_ids':ids.tolist(),
                            'added_pixels':int(additions.sum()),'bbox_xywh':bbox(additions)})
    (out/'repair_patches.json').write_text(json.dumps(repairs,indent=2))
    result['recommendation'] = 'balanced'
    (out/'metrics.json').write_text(json.dumps(result,indent=2))
    # These comparisons are derived solely from raster/contours, never world models.
    comparisons = out.parent/'comparisons';comparisons.mkdir(exist_ok=True)
    imgs=[original_render]+[Image.open(out/f'map_display_{v}.png') for v in PARAMS]
    compose(imgs,['Original palette','A Conservative','B Balanced','C Aggressive (comparison only)'],comparisons/'variants.png')
    compose([Image.open(out/f'closing_{r}_cells.png') for r in [1,2,3]],
            [f'Closing radius {r} cells / {r*resolution*100:.1f} cm' for r in [1,2,3]],comparisons/'closing_1_2_3.png',3)
    overlay=np.array(original_render);overlay[boundary(occupied)]=(226,73,96);overlay[boundary(variants['balanced'])]=(0,137,167)
    Image.fromarray(overlay).save(comparisons/'original_balanced_boundary_overlay.png')
    diff=np.zeros((*occupied.shape,3),dtype='uint8');diff[:]=(233,236,239);diff[occupied & variants['balanced']]=(53,63,73)
    diff[occupied & ~variants['balanced']]=(226,73,96);diff[variants['balanced'] & ~occupied]=(0,137,167)
    Image.fromarray(diff).save(comparisons/'occupied_diff.png')
    lab,sizes=components(occupied);pillar_boxes=[]
    for label in range(1,len(sizes)):
        x,y,w,h=bbox(lab==label)
        if 5<=w<=24 and 5<=h<=24 and sizes[label]>=15:pillar_boxes.append([x,y,w,h])
    (out/'pillar_candidates_from_raster.json').write_text(json.dumps(pillar_boxes,indent=2))
    pillar_metrics=[]
    for i,(x,y,w,h) in enumerate(pillar_boxes):
        row={'raster_candidate':i+1,'bbox_xywh':[x,y,w,h]}
        for name,mask in [('original',occupied),*variants.items()]:
            crop=mask[max(0,y-3):y+h+3,max(0,x-3):x+w+3]
            cs=contours(crop,cv2.RETR_EXTERNAL)[0]
            c=max(cs,key=cv2.contourArea)
            perimeter=cv2.arcLength(c,True)
            row[name+'_circularity']=float(4*math.pi*cv2.contourArea(c)/perimeter**2) if perimeter else 0
        pillar_metrics.append(row)
    result['pillar_circularity']=pillar_metrics
    # Export a second, directly image-derived mask, to expose antialias/coverage differences.
    for name in PARAMS:
        displayed=np.array(Image.open(out/f'map_display_{name}.png'))[:,:,0] < 140
        save_mask(out/f'occupied_display_threshold_{name}.png',displayed)
        result['variants'][name]['display_threshold_r_lt_140']=metrics(displayed,occupied,resolution)
    (out/'metrics.json').write_text(json.dumps(result,indent=2))

    if pillar_boxes:
        x=min(b[0] for b in pillar_boxes)-12;y=min(b[1] for b in pillar_boxes)-12
        right=max(b[0]+b[2] for b in pillar_boxes)+12;bottom=max(b[1]+b[3] for b in pillar_boxes)+12
        compose([im.crop((x,y,right,bottom)).resize(((right-x)*3,(bottom-y)*3),Image.NEAREST) for im in [original_render,imgs[2]]],
                ['Pillars - original','Pillars - balanced'],comparisons/'pillars_zoom.png')
    added=variants['balanced'] & ~occupied
    # Most additions outside compact pillar candidates identify a real repaired wall patch.
    wall_additions=added.copy()
    for x,y,w,h in pillar_boxes:wall_additions[max(0,y-4):y+h+4,max(0,x-4):x+w+4]=False
    density=ndi.uniform_filter(wall_additions.astype(float),size=35)
    py,px=np.unravel_index(density.argmax(),density.shape)
    crop=(max(0,px-45),max(0,py-35),min(image.shape[1],px+45),min(image.shape[0],py+35))
    compose([im.crop(crop).resize(((crop[2]-crop[0])*5,(crop[3]-crop[1])*5),Image.NEAREST) for im in [original_render,imgs[2]]],
            ['Wall patch - original','Wall patch - balanced'],comparisons/'wall_gap_zoom.png')
    (out/'wall_patch_bbox.json').write_text(json.dumps([int(v) for v in crop]))
    print(json.dumps(result['variants'],indent=2))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    run(args.inputs,args.output)

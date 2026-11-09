#!/usr/bin/env python3
"""SLAM-derived display assets only. No world, ROS, server or navigation outputs."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import cairo
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
import yaml

import b4_core as core

SCALE = 4
AA_SCALE = 8
DP_EPSILON = .35  # native cell units = 1.75cm at this map's resolution


def world(points, meta):
    p = np.asarray(points, dtype=float)
    x, y = p[...,0]*meta['resolution'], (meta['height']-p[...,1])*meta['resolution']
    ox,oy,yaw = meta['origin']; c,s=math.cos(yaw),math.sin(yaw)
    return np.stack([ox+c*x-s*y,oy+s*x+c*y],axis=-1).tolist()


def cell_loops(mask):
    """Trace exact cell edges, including holes; coordinates are grid CORNERS.

    OpenCV center contours remain available for analysis/fitting. This boundary
    extraction avoids shrinking a one-cell wall by using its pixel centers as edges.
    At a diagonal contact, turn right to keep the occupied cell on the right.
    """
    edges={}
    h,w=mask.shape
    def add(a,b): edges.setdefault(a,set()).add(b)
    for y,x in zip(*np.where(mask)):
        x,y=int(x),int(y)
        if y==0 or not mask[y-1,x]:add((x,y),(x+1,y))
        if x==w-1 or not mask[y,x+1]:add((x+1,y),(x+1,y+1))
        if y==h-1 or not mask[y+1,x]:add((x+1,y+1),(x,y+1))
        if x==0 or not mask[y,x-1]:add((x,y+1),(x,y))
    loops=[];directions={(1,0):0,(0,1):1,(-1,0):2,(0,-1):3};priority={1:0,0:1,3:2,2:3}
    while edges:
        start=min(edges);a=start;b=min(edges[a]);loop=[a]
        while True:
            incoming=directions[(b[0]-a[0],b[1]-a[1])]
            edges[a].remove(b)
            if not edges[a]:del edges[a]
            a,b=b,None
            if a==start:break
            loop.append(a)
            b=min(edges[a],key=lambda q:priority[(directions[(q[0]-a[0],q[1]-a[1])]-incoming)%4])
        loops.append(loop)
    return loops


def path(ctx, loops):
    ctx.new_path()
    for loop in loops:
        if len(loop)<3:continue
        ctx.move_to(*loop[0])
        for point in loop[1:]:ctx.line_to(*point)
        ctx.close_path()
    ctx.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)


def loop_alpha(loops, box, scale=AA_SCALE):
    x,y,w,h=box
    surface=cairo.ImageSurface(cairo.FORMAT_A8,w*scale,h*scale)
    ctx=cairo.Context(surface);ctx.scale(scale,scale);ctx.translate(-x,-y)
    path(ctx,loops);ctx.set_source_rgba(1,1,1,1);ctx.fill();surface.flush()
    return np.frombuffer(surface.get_data(),np.uint8).reshape(h*scale,surface.get_stride())[:,:w*scale].copy()


def roi(mask,box):
    x,y,w,h=box
    return mask[y:y+h,x:x+w]


def bounds(part):
    x,y,w,h=core.bbox(part)
    x0,y0=max(0,x-2),max(0,y-2)
    return [x0,y0,min(part.shape[1],x+w+2)-x0,min(part.shape[0],y+h+2)-y0]


def coverage_metrics(before,alpha,unknown,box,scale=AA_SCALE):
    # Compare at the actual subcell render scale, not only rounded grid vertices.
    old=np.repeat(np.repeat(roi(before,box),scale,0),scale,1)
    new=alpha>=128
    un=np.repeat(np.repeat(roi(unknown,box),scale,0),scale,1)
    new &= ~un
    bd_old=core.boundary(old);bd_new=core.boundary(new)
    if not new.any():return None
    displacement=max(float(core.distance(bd_old)[bd_new].max(initial=0)),
                     float(core.distance(bd_new)[bd_old].max(initial=0)))/scale
    native=(new.reshape(box[3],scale,box[2],scale).mean(axis=(1,3))>=.5)
    source=roi(before,box)
    return {'local_iou':float((old & new).sum()/max(1,(old | new).sum())),
            'maximum_geometric_offset_cells':displacement,
            'changed_native_pixels':int((source!=native).sum()),
            'added_native_pixels':int((native & ~source).sum()),
            'removed_native_pixels':int((source & ~native).sum()),
            'changed_subpixels':int((old!=new).sum()),
            'proposed_unknown_subpixels':int(((alpha>=128)&un).sum()),
            'applied_unknown_subpixels':0},native


def audit(kind,before,after_loops,unknown,meta,minimum_iou=.9,limit=.5,source_original=None):
    box=bounds(before);alpha=loop_alpha(after_loops,box)
    measured=coverage_metrics(before,alpha,unknown,box)
    if measured is None:return {'kind':kind,'accepted':False,'reason':'empty shape after known-space clipping'},None
    values,native=measured
    accepted=values['local_iou']>=minimum_iou and values['maximum_geometric_offset_cells']<=limit
    original_loops=cell_loops(before)
    # Record the applied known-space intersection, separately from the proposal.
    high=(alpha>=128) & ~np.repeat(np.repeat(roi(unknown,box),AA_SCALE,0),AA_SCALE,1)
    applied=[]
    for loop in cell_loops(high):
        compact=cv2.approxPolyDP(np.array(loop,dtype='float32')[:,None,:],0,True)[:,0,:]
        applied.append((compact/AA_SCALE+np.array(box[:2])).tolist())
    raw=before if source_original is None else source_original
    raw_hi=np.repeat(np.repeat(roi(raw,box),AA_SCALE,0),AA_SCALE,1)
    values['original_region_iou']=float((raw_hi & high).sum()/max(1,(raw_hi | high).sum()))
    values.update(kind=kind,accepted=bool(accepted),bbox_xywh=core.bbox(before),
                  maximum_geometric_offset_m=values['maximum_geometric_offset_cells']*meta['resolution'],
                  unknown_involvement=bool(values['proposed_unknown_subpixels']),
                  unknown_policy='source unknown clipped exactly; never painted occupied/free',
                  before_grid_corners=original_loops,after_grid_corners=applied,proposed_grid_corners=after_loops,
                  before_map_coordinates=[world(l,meta) for l in original_loops],
                  after_map_coordinates=[world(l,meta) for l in applied],
                  proposed_map_coordinates=[world(l,meta) for l in after_loops],
                  max_allowed_offset_m=limit*meta['resolution'],minimum_local_iou=minimum_iou)
    candidate=np.zeros_like(before);x,y,w,h=box;candidate[y:y+h,x:x+w]=native
    return values,candidate


def hough(occupied,meta):
    cv2.setRNGSeed(501)
    lines=cv2.HoughLinesP(occupied.astype('uint8')*255,1,np.pi/720,30,
                         minLineLength=40,maxLineGap=2)
    records=[]
    for line in ([] if lines is None else lines[:,0,:]):
        x1,y1,x2,y2=[int(v) for v in line]
        records.append({'grid_centers':[[x1+.5,y1+.5],[x2+.5,y2+.5]],
                        'map_endpoints':world([[x1+.5,y1+.5],[x2+.5,y2+.5]],meta),
                        'length_m':float(math.hypot(x2-x1,y2-y1)*meta['resolution'])})
    return records


def quality(occupied,free,unknown,meta,lines):
    ol,os=core.components(occupied);fl,fs=core.components(free)
    outside=core.border_connected(unknown);pillars=[];walls=[]
    for label in range(1,len(os)):
        part=ol==label;x,y,w,h=core.bbox(part)
        cnt=max(core.contours(part,cv2.RETR_EXTERNAL)[0],key=cv2.contourArea)
        area=cv2.contourArea(cnt);perimeter=cv2.arcLength(cnt,True)
        if 5<=w<=24 and 5<=h<=24 and os[label]>=15:
            center,radius,rms=core.circle_fit(cnt)
            points=np.argwhere(part)[:,::-1]
            angles=np.sort(np.arctan2(points[:,1]-center[1],points[:,0]-center[0]))
            maxgap=np.diff(np.r_[angles,angles[0]+2*np.pi]).max()
            pillars.append({'component':label,'bbox_xywh':[x,y,w,h],'occupied_pixels':int(os[label]),
                            'circularity':float(4*np.pi*area/perimeter**2) if perimeter else 0,
                            'angular_support_degrees':float(360-maxgap*180/np.pi),
                            'fit_center_grid':(center+.5).tolist(),'fit_center_map':world([center+.5],meta)[0],
                            'fit_radius_m':float(radius*meta['resolution']),'radial_rms_m':float(rms*meta['resolution']),
                            'has_observation_of_full_solid_disk':bool(part.sum()/(math.pi*radius**2)>=.85 and 4*math.pi*area/perimeter**2>=.75),
                            'conclusion':'partial/hollow or distorted scan contour; do not force circular completion'})
        if max(w,h)/min(w,h)>=8 and max(w,h)>=40:
            walls.append({'component':label,'bbox_xywh':[x,y,w,h],'occupied_pixels':int(os[label])})
    return {'metadata':meta,'counts':{'occupied':int(occupied.sum()),'free':int(free.sum()),'unknown':int(unknown.sum()),
             'unknown_percent':float(unknown.mean()*100),'occupied_components_8':len(os)-1,'free_components_8':len(fs)-1,
             'largest_free_component_pixels':int(fs[1:].max()),'occupied_components_1_or_2_pixels':int((os[1:]<=2).sum()),
             'exterior_unknown_pixels':int(outside.sum()),'other_unknown_pixels':int((unknown&~outside).sum())},
            'wall_fragments':walls,'hough_line_candidates':lines,'pillar_candidates':pillars,
            'source_metrics':core.metrics(occupied,occupied,meta['resolution']),
            'display_correctable':['palette, antialiasing, high-resolution vector representation',
                'collinear contour simplification','bounded measured-wall edge straightening within known space'],
            'requires_new_observation':['large unknown sectors','unobserved pillar backsides/partial arcs',
                'long wall gaps without occupied support'],
            'unknown_interpretation':'-1 in the authoritative frozen grid is missing map observation/information, not a removable visual artifact. Static export cannot distinguish occlusion from incomplete acquisition/export history.',
            'rescan_recommendation':'Yes, only in a future separately authorized mapping task: unknown sectors and incomplete pillar/wall contours. No world-based completion.'}


def wall_polygon(part,lines,meta):
    cnt=max(core.contours(part,cv2.RETR_EXTERNAL)[0],key=cv2.contourArea)
    rect=cv2.minAreaRect(cnt);a,b=rect[1]
    if min(a,b)<=0 or max(a,b)/min(a,b)<15 or max(a,b)*meta['resolution']<2:return None
    vx,vy,cx,cy=cv2.fitLine(cnt,cv2.DIST_L2,0,.01,.01).ravel().astype(float)
    tangent=np.array([vx,vy]);normal=np.array([-vy,vx]);center=np.array([cx+.5,cy+.5])
    points=cnt[:,0,:].astype(float)+.5
    along=(points-center)@tangent;across=(points-center)@normal
    if np.sqrt(np.mean(across**2))>.6:return None
    supported=[]
    for line in lines:
        q=np.array(line['grid_centers']);direction=q[1]-q[0];length=np.linalg.norm(direction)
        if length==0:continue
        angle=abs(float(tangent@(direction/length)))
        if angle>=math.cos(math.radians(5)) and np.min(np.abs((q-center)@normal))<=1.5:
            supported.append(line)
    if not supported:return None
    # Pixel extent, not just contour-center extent. No extrapolation beyond this component.
    lo,hi=along.min()-.5,along.max()+.5
    thickness=max(.75,min(2.,part.sum()/max(1,hi-lo)))
    poly=[center+t*tangent+s*normal for t,s in [(lo,-thickness/2),(hi,-thickness/2),(hi,thickness/2),(lo,thickness/2)]]
    return [np.array(poly).tolist()]


def process(occupied,free,unknown,meta,lines):
    # Only observed free cells may change class. Never fill unknown or infer exterior walls.
    closed=occupied | (core.close_small(occupied,1) & free)
    edits=[];delta=closed & ~occupied;lab,sizes=core.components(delta)
    for label in range(1,len(sizes)):
        patch=lab==label;near=ndi.binary_dilation(patch,iterations=1)&occupied
        before=near;after=near|patch
        rec,_=audit('morphology_radius_1_cell',before,cell_loops(after),unknown,meta,minimum_iou=0,limit=1)
        rec['accepted']=True;rec['added_grid_cell_centers']=(np.argwhere(patch)[:,::-1]+.5).tolist()
        rec['added_map_coordinates']=world(rec['added_grid_cell_centers'],meta)
        edits.append(rec)
    layers=[];native=closed.copy();labels,counts=core.components(closed)
    for label in range(1,len(counts)):
        part=labels==label;original_loops=cell_loops(part)
        simplified=[cv2.approxPolyDP(np.array(l,dtype='float32')[:,None,:],DP_EPSILON,True)[:,0,:].tolist() for l in original_loops]
        loops=original_loops
        if any(len(l)>=4 for l in original_loops) and all(len(l)>=3 for l in simplified):
            rec,candidate=audit('douglas_peucker',part,simplified,unknown,meta,.96,.5,occupied & part)
            rec['component']=label;rec['epsilon_m']=DP_EPSILON*meta['resolution']
            rec['representation_vertices_before']=sum(len(l) for l in original_loops)
            rec['representation_vertices_after']=sum(len(l) for l in simplified)
            edits.append(rec)
            if rec['accepted']:loops=simplified
        wall=wall_polygon(part,lines,meta)
        if wall is not None:
            rec,candidate=audit('hough_supported_wall_line',part,wall,unknown,meta,.75,1,occupied & part)
            rec['component']=label;edits.append(rec)
            if rec['accepted']:loops=wall
        # Circle support is assessed from the source contour, never from a world model.
        x,y,w,h=core.bbox(part)
        if 5<=w<=24 and 5<=h<=24 and counts[label]>=15:
            cnt=max(core.contours(part,cv2.RETR_EXTERNAL)[0],key=cv2.contourArea)
            center,radius,rms=core.circle_fit(cnt);area=cv2.contourArea(cnt);per=cv2.arcLength(cnt,True)
            circ=4*np.pi*area/per**2 if per else 0
            occupied_points=np.argwhere(part)[:,::-1]
            angles=np.sort(np.arctan2(occupied_points[:,1]-center[1],occupied_points[:,0]-center[0]))
            angular_support=2*np.pi-np.diff(np.r_[angles,angles[0]+2*np.pi]).max()
            solid_fraction=part.sum()/(math.pi*(radius+.5)**2)
            if circ>=.75 and .15<=(radius+.5)*meta['resolution']<=.5 and rms<=radius*.1 and angular_support>=math.radians(330) and solid_fraction>=.85:
                theta=np.linspace(0,2*np.pi,128,endpoint=False)
                circle=[np.c_[center[0]+.5+(radius+.5)*np.cos(theta),center[1]+.5+(radius+.5)*np.sin(theta)].tolist()]
                rec,candidate=audit('evidence_supported_circle',part,circle,unknown,meta,.9,1,occupied & part)
                rec['component']=label;edits.append(rec)
                if rec['accepted']:loops=circle
        # Native semantic-mask statistics are derived from the final subpixel geometry.
        box=bounds(part);alpha=loop_alpha(loops,box)
        values,candidate=coverage_metrics(part,alpha,unknown,box)
        native[part]=False;x0,y0,ww,hh=box;native[y0:y0+hh,x0:x0+ww] |= candidate
        layers.append(loops)
    return layers,native,edits


def path_d(loops):
    return ' '.join('M '+' L '.join(f'{x:.6g},{y:.6g}' for x,y in l)+' Z' for l in loops if len(l)>=3)


def svg_file(file,known_loops,occupied_layers,meta,professional):
    w,h=meta['width'],meta['height']
    background='#E8EEF3' if professional else '#E9ECEF'
    free='#FAFCFD' if professional else '#FCFDFE';wall='#344254' if professional else '#353F49'
    known=path_d(known_loops)
    chunks=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w*SCALE}" height="{h*SCALE}" viewBox="0 0 {w} {h}">',
            '<metadata>'+json.dumps({'display_only':True,'displayScale':SCALE,'native_width':w,'native_height':h,
                'resolution':meta['resolution'],'origin':meta['origin'],'physical_extent_m':[w*meta['resolution'],h*meta['resolution']]})+'</metadata>',
            f'<defs><clipPath id="known"><path d="{known}" clip-rule="evenodd"/></clipPath>',
            '<pattern id="unknown-hatch" width="12" height="12" patternUnits="userSpaceOnUse"><path d="M -12,12 L 12,-12 M 0,24 L 24,0" stroke="#DAE3EB" stroke-width="0.12"/></pattern></defs>',
            f'<rect width="{w}" height="{h}" fill="{background}"/>']
    if professional:chunks.append(f'<rect width="{w}" height="{h}" fill="url(#unknown-hatch)"/>')
    chunks.append(f'<path d="{known}" fill="{free}" fill-rule="evenodd"/>')
    chunks.append(f'<g clip-path="url(#known)" fill="{wall}" fill-rule="evenodd">')
    chunks.extend(f'<path d="{path_d(loops)}"/>' for loops in occupied_layers)
    chunks.extend(['</g>','</svg>']);file.write_text('\n'.join(chunks))


def png_file(file,known_loops,occupied_layers,meta,professional):
    w,h=meta['width'],meta['height'];s=AA_SCALE
    surface=cairo.ImageSurface(cairo.FORMAT_ARGB32,w*s,h*s);ctx=cairo.Context(surface);ctx.scale(s,s)
    def color(rgb):ctx.set_source_rgb(*[v/255 for v in rgb])
    color((232,238,243) if professional else (233,236,239));ctx.paint()
    if professional:
        color((218,227,235));ctx.set_line_width(.12)
        for offset in range(-h,w+1,12):ctx.move_to(offset,0);ctx.line_to(offset-h,h)
        ctx.stroke()
    path(ctx,known_loops);color((250,252,253) if professional else (252,253,254));ctx.fill_preserve();ctx.clip()
    color((52,66,84) if professional else (53,63,73))
    for loops in occupied_layers:path(ctx,loops);ctx.fill()
    surface.flush();array=np.frombuffer(surface.get_data(),np.uint8).reshape(h*s,surface.get_stride())[:,:w*s*4].reshape(h*s,w*s,4)
    image=Image.fromarray(array[:,:,[2,1,0]].copy(),'RGB')
    image.resize((w*SCALE,h*SCALE),Image.LANCZOS).save(file)


def compare(images,labels,file):
    width,height=2044,2640;font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',40)
    canvas=Image.new('RGB',(width*len(images),height+80),'white');draw=ImageDraw.Draw(canvas)
    for i,(image,label) in enumerate(zip(images,labels)):
        canvas.paste(image.resize((width,height),Image.NEAREST if image.width<width else Image.LANCZOS),(i*width,80));draw.text((i*width+16,16),label,font=font,fill='#263746')
    canvas.save(file)


def run(root):
    inputs,out,comparisons=root/'inputs',root/'outputs',root/'comparisons'
    image=np.asarray(Image.open(inputs/'map.pgm'));config=yaml.safe_load((inputs/'map.yaml').read_text())
    occupied,free,unknown=core.classify(image,config)
    meta={'width':image.shape[1],'height':image.shape[0],'resolution':config['resolution'],'origin':config['origin']}
    for name,mask in [('occupied',occupied),('free',free),('unknown',unknown)]:core.save_mask(out/f'original_{name}.png',mask)
    lines=hough(occupied,meta);q=quality(occupied,free,unknown,meta,lines)
    (root/'RAW_MAP_QUALITY.json').write_text(json.dumps(q,indent=2))
    (out/'hough_lines.json').write_text(json.dumps(lines,indent=2))
    (out/'occupied_contours_original.json').write_text(json.dumps(core.contour_json(occupied)))
    labels,_=core.components(occupied)
    wall_contours=[]
    for wall in q['wall_fragments']:
        loops=cell_loops(labels==wall['component'])
        wall_contours.append({**wall,'grid_corners':loops,'map_coordinates':[world(l,meta) for l in loops]})
    (out/'wall_contours_original.json').write_text(json.dumps(wall_contours,indent=2))
    # Source quality facts above are recorded before any geometric processing.
    layers,native,edits=process(occupied,free,unknown,meta,lines)
    (out/'geometry_audit.json').write_text(json.dumps(edits,indent=2))
    known_loops=cell_loops(~unknown)
    original_layers=[cell_loops(occupied)]
    variants={'faithful_vector':(original_layers,occupied,False),
              'conservative_geometry':(layers,native,False),
              'professional_floorplan':(layers,native,True)}
    metrics={}
    for name,(layer,mask,professional) in variants.items():
        svg_file(out/f'map_{name}.svg',known_loops,layer,meta,professional)
        png_file(out/f'map_{name}.png',known_loops,layer,meta,professional)
        core.save_mask(out/f'occupied_{name}.png',mask)
        core.save_mask(out/f'free_{name}.png',~(mask|unknown));core.save_mask(out/f'unknown_{name}.png',unknown)
        stats=core.metrics(mask,occupied,meta['resolution'])
        stats.update(displayScale=SCALE,output_width=meta['width']*SCALE,output_height=meta['height']*SCALE,
                     unknown_changed_pixels=int((unknown & mask).sum()),source_pgm_sha256=hashlib.sha256((inputs/'map.pgm').read_bytes()).hexdigest(),
                     accepted_modifications=sum(e['accepted'] for e in edits) if name!='faithful_vector' else 0)
        (out/f'metrics_{name}.json').write_text(json.dumps(stats,indent=2));metrics[name]=stats
        original=Image.fromarray(image).convert('RGB');processed=Image.open(out/f'map_{name}.png')
        compare([original,processed],['Raw SLAM PGM',name.replace('_',' ')],comparisons/f'{name}_vs_original.png')
        for tag,crop in [('walls',(90,0,511,40)),('eight_pillars',(105,340,410,540))]:
            a=original.crop(crop);b=processed.crop(tuple(v*SCALE for v in crop))
            zoom=Image.new('RGB',(a.width*4*2,a.height*4+80),'white');draw=ImageDraw.Draw(zoom)
            draw.text((8,10),'Source SLAM',font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',32),fill='#263746');draw.text((a.width*4+8,10),name,font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',32),fill='#263746')
            zoom.paste(a.resize((a.width*4,a.height*4),Image.NEAREST),(0,80));zoom.paste(b.resize((a.width*4,a.height*4),Image.LANCZOS),(a.width*4,80));zoom.save(comparisons/f'{name}_{tag}_zoom.png')
        diff=np.zeros((*mask.shape,3),dtype=np.uint8);diff[:]=(233,236,239);diff[occupied&mask]=(53,63,73);diff[mask&~occupied]=(0,137,167);diff[occupied&~mask]=(226,73,96)
        Image.fromarray(diff).resize((meta['width']*SCALE,meta['height']*SCALE),Image.NEAREST).save(comparisons/f'{name}_occupied_diff.png')
    compare([Image.open(out/f'map_{name}.png') for name in variants],['A Faithful Vector','B Conservative Geometry','C Professional Floorplan'],comparisons/'three_candidates.png')
    (out/'metrics.json').write_text(json.dumps(metrics,indent=2))
    (out/'render_metadata.json').write_text(json.dumps({**meta,'scale':SCALE,'displayScale':SCALE,'display_only':True,
        'width':meta['width'],'height':meta['height'],'pixel_width':meta['width']*SCALE,'pixel_height':meta['height']*SCALE,
        'recommended':'professional_floorplan','anti_alias_render_scale':AA_SCALE,'unknown_policy':'unchanged'},indent=2))
    print(json.dumps({'quality':q['counts'],'hough_lines':len(lines),'edits':len(edits),
                      'accepted':{k:sum(e['accepted'] and e['kind']==k for e in edits) for k in set(e['kind'] for e in edits)},'metrics':metrics},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True)
    run(parser.parse_args().root)

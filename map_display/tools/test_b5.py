import hashlib
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
import yaml

import render_b5 as renderer

ROOT=Path(__file__).resolve().parents[1]


class B5Tests(unittest.TestCase):
    def test_authoritative_grid_classification_and_input_sha(self):
        image=np.asarray(Image.open(ROOT/'inputs/map.pgm'))
        config=yaml.safe_load((ROOT/'inputs/map.yaml').read_text())
        occ,free,unknown=renderer.core.classify(image,config)
        grid=json.loads((ROOT/'inputs/occupancy_grid.json').read_text())
        data=np.array(grid['data']).reshape(image.shape)[::-1]
        self.assertTrue(np.array_equal(occ,data==100));self.assertTrue(np.array_equal(free,data==0))
        self.assertTrue(np.array_equal(unknown,data==-1))
        frozen=json.loads((ROOT/'inputs/a7-asset-sha256.json').read_text())
        for name in ['map.pgm','map.yaml','occupancy_grid.json']:
            expected=[sha for p,sha in frozen.items() if Path(p).name==name][0]
            self.assertEqual(hashlib.sha256((ROOT/'inputs'/name).read_bytes()).hexdigest(),expected)

    def test_exact_cell_edge_vectors_preserve_holes_and_diagonal_contacts(self):
        mask=np.zeros((18,18),bool);mask[2:12,2:12]=True;mask[5:9,5:9]=False
        mask[12,12]=True;mask[13,13]=True;mask[1,16]=True
        alpha=renderer.loop_alpha(renderer.cell_loops(mask),[0,0,18,18])
        self.assertTrue(np.array_equal(alpha>=128,np.repeat(np.repeat(mask,8,0),8,1)))

    def test_png_svg_dimensions_physical_extent_and_faithful_semantics(self):
        q=json.loads((ROOT/'RAW_MAP_QUALITY.json').read_text());meta=q['metadata'];w,h=meta['width'],meta['height']
        for name in ['faithful_vector','conservative_geometry','professional_floorplan']:
            png=Image.open(ROOT/f'outputs/map_{name}.png');self.assertEqual(png.size,(w*4,h*4));png.close()
            svg=ET.parse(ROOT/f'outputs/map_{name}.svg').getroot()
            self.assertEqual(svg.attrib['viewBox'],f'0 0 {w} {h}')
            self.assertEqual(int(svg.attrib['width']),w*4);self.assertEqual(int(svg.attrib['height']),h*4)
            sm=json.loads(svg.find('{http://www.w3.org/2000/svg}metadata').text)
            self.assertEqual(sm['origin'],meta['origin']);self.assertEqual(sm['resolution'],meta['resolution'])
            self.assertEqual(sm['physical_extent_m'],[w*meta['resolution'],h*meta['resolution']])
            self.assertFalse(any(tag.tag.endswith('image') for tag in svg.iter()))
        raw=np.asarray(Image.open(ROOT/'inputs/map.pgm'))
        png=np.asarray(Image.open(ROOT/'outputs/map_faithful_vector.png'))[2::4,2::4,:3].astype(float)
        colors=np.array([[53,63,73],[252,253,254],[233,236,239]])
        labels=np.linalg.norm(png[:,:,None,:]-colors,axis=3).argmin(axis=2)
        expected=np.where(raw==0,0,np.where(raw==255,1,2))
        self.assertTrue(np.array_equal(labels,expected))

    def test_unknown_and_tristate_partition_preserved(self):
        unknown=np.asarray(Image.open(ROOT/'outputs/original_unknown.png'))>0
        for name in ['faithful_vector','conservative_geometry','professional_floorplan']:
            masks=[np.asarray(Image.open(ROOT/f'outputs/{kind}_{name}.png'))>0 for kind in ['occupied','free','unknown']]
            self.assertTrue(np.array_equal(masks[2],unknown))
            self.assertTrue(np.all(sum(m.astype(int) for m in masks)==1))

    def test_hough_detects_observed_line_and_unknown_gap_cannot_be_filled(self):
        occ=np.zeros((36,100),bool);occ[16:19,3:45]=True;occ[16:19,46:92]=True
        unknown=np.zeros_like(occ);unknown[:,45]=True
        meta={'width':100,'height':36,'origin':[-1,2,0],'resolution':.05}
        lines=renderer.hough(occ,meta);self.assertGreater(len(lines),0)
        _,result,edits=renderer.process(occ,~(unknown|occ),unknown,meta,lines)
        self.assertFalse(result[:,45].any());self.assertFalse((result&unknown).any())
        self.assertTrue(all(e.get('applied_unknown_subpixels',0)==0 for e in edits))

    def test_circle_requires_solid_angular_and_radial_evidence(self):
        yy,xx=np.mgrid[:45,:45];circle=(xx-22)**2+(yy-22)**2<=9**2
        meta={'width':45,'height':45,'origin':[0,0,0],'resolution':.05}
        _,_,edits=renderer.process(circle,~circle,np.zeros_like(circle),meta,[])
        self.assertTrue(any(e['kind']=='evidence_supported_circle' and e['accepted'] for e in edits))
        partial=circle.copy();partial[22:,22:]=False
        _,_,edits=renderer.process(partial,~partial,np.zeros_like(partial),meta,[])
        self.assertFalse(any(e['kind']=='evidence_supported_circle' and e['accepted'] for e in edits))

    def test_audit_contains_actual_before_after_coordinates_and_bounds(self):
        rows=json.loads((ROOT/'outputs/geometry_audit.json').read_text())
        meta=json.loads((ROOT/'RAW_MAP_QUALITY.json').read_text())['metadata']
        count=0
        for row in rows:
            if not row['accepted']:continue
            for field in ['changed_native_pixels','maximum_geometric_offset_m','original_region_iou',
                          'before_grid_corners','after_grid_corners','before_map_coordinates','after_map_coordinates','unknown_involvement']:
                self.assertIn(field,row)
            self.assertEqual(row['applied_unknown_subpixels'],0)
            self.assertLessEqual(row['maximum_geometric_offset_m'],row['max_allowed_offset_m']+1e-12)
            for grid,world in zip(row['after_grid_corners'],row['after_map_coordinates']):
                self.assertTrue(np.allclose(renderer.world(grid,meta),world,atol=1e-12))
            count+=1
        self.assertGreater(count,0)
        self.assertEqual(json.loads((ROOT/'outputs/metrics_faithful_vector.json').read_text())['iou'],1)


if __name__=='__main__':unittest.main(verbosity=2)

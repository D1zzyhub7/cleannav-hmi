# References and dependency licenses

This is a small local implementation using installed libraries. No third-party repository/source file was vendored or copied wholesale. The script does not import ROS and never reads a world file.

- [OpenCV 4.5.4 morphological transformations](https://docs.opencv.org/4.5.4/d9/d61/tutorial_py_morphological_ops.html): `morphologyEx`, ellipse kernels; closing followed by an explicit Euclidean distance bound.
- [OpenCV 4.5.4 contour features](https://docs.opencv.org/4.5.4/dd/d49/tutorial_py_contour_features.html): `findContours`, area/perimeter, rectangle geometry. `fitLine` fits only supported long thin components; circle center/radius are fitted from raster contour samples with NumPy least squares.
- [OpenCV license](https://opencv.org/license/): OpenCV 4.5.0+ uses Apache-2.0; installed version 4.5.4.
- [Nav2 Humble map_io.cpp](https://github.com/ros-navigation/navigation2/blob/humble/nav2_map_server/src/map_io.cpp): threshold/negate/trinary and row-orientation semantics; source file carries a BSD-3-Clause-style notice. Only semantics were referenced, no source was copied. Authoritative actual thresholds come from the frozen map.yaml, not defaults in documentation.
- [NumPy license](https://github.com/numpy/numpy/blob/v1.21.5/LICENSE.txt): BSD-3-Clause. Installed 1.21.5.
- [SciPy license](https://github.com/scipy/scipy/blob/v1.8.0/LICENSE.txt): BSD-3-Clause; `ndimage.label`, binary propagation/fill, Euclidean distance transform. Installed 1.8.0.
- [Pillow license](https://github.com/python-pillow/Pillow/blob/9.0.1/LICENSE): HPND/PIL license; 4x polygon/circle raster composition and Lanczos downsampling. Installed 9.0.1.
- [PyYAML license](https://github.com/yaml/pyyaml/blob/5.4.1/LICENSE): MIT. Installed 5.4.1.

scikit-image is not installed and was not added. Its small-object/hole operations are not required because existing SciPy connected-component operations provide the needed behavior. No neural network, runtime pipeline, state framework, node, API, service, Gate or Observer was added.


## B5 additions (all already installed; no package installation)

- [OpenCV HoughLinesP](https://docs.opencv.org/4.5.4/d9/db0/tutorial_hough_lines.html): observed straight-line detection; gaps up to2native cells are only detection candidates, never permission to fill unknown.
- [OpenCV approxPolyDP](https://docs.opencv.org/4.5.4/dd/d49/tutorial_py_contour_features.html): Douglas-Peucker simplification of cell-edge contours.
- [Pycairo ImageSurface](https://pycairo.readthedocs.io/en/latest/reference/surfaces.html): installed Pycairo1.20.1/Cairo1.16.0 used offline for subpixel drawing, with no APP dependency. Installed copyright declares LGPL2.1 or MPL1.1; see /usr/share/doc/python3-cairo/copyright and [Pycairo project](https://github.com/pygobject/pycairo). Source is not vendored.
- [W3C SVG viewBox](https://www.w3.org/TR/SVG2/coords.html#ViewBoxAttribute): output viewport2044x2640 with viewBox0 0 511 660, preserving native physical extent. SVG is actual vector geometry, no embedded raster.

B5 copies its own B4 helper source into tools/b4_core.py so imports cannot create bytecode inside the frozen B4 directory. B5 never executes B4's CLI or its world-reference checker. No third-party project is copied.

Reproduce from the B5 directory:

```bash
python3 tools/render_b5.py --root .
python3 tools/test_b5.py
```

Only inputs/map.pgm, inputs/map.yaml and local output/configuration are renderer inputs. World data is neither imported nor read. Recommended APP image: outputs/map_professional_floorplan.png. A provides an exact-semantic fallback.

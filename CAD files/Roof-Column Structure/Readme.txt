Requirements: OpenSCAD

Scripts and OpenSCAD files to generate a 3D-printable roof-column structure for dynamical experiments. The structure is fully parameterized, where the spring stiffnesses can be changed based on thickness, number of windings etc. The roof can either be made with two or four springs.
A script (for Linux) is provided to export stl files for 3D-printing for the springs and the plate. An stl for the full assembly based on number of springs and number of storeys is also generated.
Attachement holes for MPU6050 sensors are included.

Usage:

- Change parameters to desired layout in scripts/Modules.scad, press F5 in OpenSCAD to view the model
- Run compile.sh from command line (Linux) to generate stl-files

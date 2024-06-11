#!/bin/bash

openscad ./scripts/3D-Feder.scad -o Feder.stl
openscad ./scripts/Baseplate.scad -o Platte.stl
openscad ./scripts/Assembly.scad -o Assembly.stl

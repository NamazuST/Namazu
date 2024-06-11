include <Modules.scad>

difference() {
    Plate();
    translate([wPlate,0,0])cube([50,50,50],center=true);
}
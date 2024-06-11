include <Modules.scad>

MPUattachments = 0;
dHole = 0;
nutS = 0;

module Assembly() {
        translate([0,0,wBase/2])
        for (i=[0:nStoreys-1]) {
            translate([0,0,i*storeyHeight])
            Storey();
        }
}

Assembly();
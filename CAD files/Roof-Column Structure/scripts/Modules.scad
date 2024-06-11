$fn = 50;

//PLATE
l = 150; // length/width of plate
wPlate =30; // thickness of plate

// M2 - DIN 934
// dHole = 2.2;
nutS = 4.2;

// M3
dHole = 3.2;
//nutS = 5.8;

// M4
// dHole = 4.2;
// nutS = 7.2;

//SPRINGS
e = 40; // size of base plate for springs
wBase = 5; // thickness of spring base
w = 2; // thickness of springs

springCurve = 2; // radius of curve windings
sh = 5; // height of spring attachement base
nSpring = 8; // number of spring windings
nStoreys = 1; // number of storeys

//ASSEMBLY
squared = 1; // square or rectangular model
MPUattachments = 1; // leave holes to attach MPU6050 accelerometers
attWidthMpl = 5; // thickness of middle of plate
BaseplateCutout = 0; // cut middle out of plate
BaseplateRotate = 1; // flip plate
SpringRotate = 1; // flip springs so assembly is symmetric

/////////////////////////////////////////
springHeight = 2*sh+wBase*3/2+nSpring*(2*springCurve+w)-w;
storeyHeight = springHeight+wBase/2+wPlate;

module baseplate(e,wBase,w,dHole,sh) {

    union(){
    difference() {
            cube([e,e,wBase],center=true);
        for (i=[0:3]) {
            //screw holes
            rotate([0,0,90*i])
            translate([e/2-dHole,e/2-dHole,-wBase])
            rotate_extrude(angle=360, convexity = 2)
            square([dHole/2,wBase*2]);
        }
        if (wPlate>5) {
            if (squared) {
           translate([e/2-dHole,-e/2+dHole,wPlate/2-5])cube([nutS,nutS+dHole*3,4],center=true);
            translate([-e/2+dHole,e/2-dHole,wPlate/2-5])cube([nutS+dHole*3,nutS,4],center=true);
            translate([e/2-dHole,-e/2+dHole,-wPlate/2+5])cube([nutS,nutS+dHole*3,4],center=true);
            translate([-e/2+dHole,e/2-dHole,-wPlate/2+5])cube([nutS+dHole*3,nutS,4],center=true);
            }
        else {
            translate([e/2-dHole,-e/2+dHole,wPlate/2-5])cube([nutS,nutS+dHole*3,4],center=true);
            translate([-e/2+dHole,e/2-dHole,wPlate/2-5])cube([nutS+dHole*3,nutS,4],center=true);
            translate([e/2-dHole,-e/2+dHole,-wPlate/2+5])cube([nutS,nutS+dHole*3,4],center=true);
            translate([-e/2+dHole,e/2-dHole,-wPlate/2+5])cube([nutS+dHole*3,nutS,4],center=true);
        }
        }
        }
        if (sh>0){
            translate([-e/2,-w/2,wBase/2])cube([e,w,sh]);
        }
    }
}

module spring(e,w,curve) {
    union() {
        translate([-e/2,0,0])cube([e,e/4,w]);
        translate([e/2,e/4,curve+w])
        rotate([0,-90,0])
        rotate_extrude(angle=180, convexity = 2)
        translate([curve,0,0])
        square([w,e]);
        translate([-e/2,0,(curve)*2+w])cube([e,e/4,w]);
    }
}

module Feder() {
union() {
    baseplate(e,wBase,w,dHole,sh);
    translate([0,0,sh+wBase/2-w])
    for (i=[0:(nSpring-1)]) {
        translate([0,0,i*(2*springCurve+w)])
        rotate([0,0,180 * (i%2)])
        spring(e,w,springCurve);
    }
    translate([0,0,2*sh+wBase+nSpring*(2*springCurve+w)-w])
    rotate([180,0,0])
    baseplate(e,wBase,w,dHole,sh);
}

}

module Plate() {

if (!squared) {
    difference() {
    union() {
        baseplate(e,wPlate,w,dHole,0);
        translate([e/2,-e/2,-wPlate/2])cube([l-2*e,e,wPlate]);
        translate([l-e,0,0])baseplate(e,wPlate,w,dHole,0);
        if (MPUattachments) {
            translate([(l/2-17.05/2)-e/2,0,wPlate/2])
            cylinder(d=4,h=5);
            translate([(l/2+17.05/2)-e/2,0,wPlate/2])
            cylinder(d=4,h=5);
        }
    }
    if (MPUattachments) {
            translate([(l/2-17.05/2)-e/2,0,-wPlate/2])
            cylinder(d=1.8,h=5+wPlate);
            translate([(l/2+17.05/2)-e/2,0,-wPlate/2])
            cylinder(d=1.8,h=5+wPlate);
        }
        
    if (BaseplateCutout) {
        translate([e/2+w/2,-e/2+w/2,-wPlate/2+w])cube([l-2*e-w,e-w,wPlate]);
    }
    }
}
else {
    difference() {
        
        union() {
        baseplate(e,wPlate,w,dHole,0);
        translate([l-e,0,0])rotate([0,0,90])baseplate(e,wPlate,w,dHole,0);
        translate([0,l-e,0])rotate([0,0,270])baseplate(e,wPlate,w,dHole,0);
        translate([l-e,l-e,0])rotate([0,0,180])baseplate(e,wPlate,w,dHole,0);
        translate([e/2,-e/2,-wPlate/2])cube([l-2*e,l,wPlate]);
        rotate([0,0,90])translate([e/2,-l+e/2,-wPlate/2])cube([l-2*e,l,wPlate]);
        }
        
    if (MPUattachments) {
        
        translate([e/2,e/2,-wPlate/2+w*attWidthMpl])cube([l-2*e,l-2*e,wPlate+w*attWidthMpl]);
        
        if (BaseplateCutout) {
        
        translate([e/2,e/2,-wPlate/2])cube([(l-2*e)/2-w*attWidthMpl*2,(l-2*e)/2-w*attWidthMpl*2,wPlate]);
        
        translate([e/2+(l-2*e)/2+2*attWidthMpl,e/2,-wPlate/2])cube([(l-2*e)/2-w*attWidthMpl*2,(l-2*e)/2-w*attWidthMpl*2,wPlate]);
        
         translate([e/2+(l-2*e)/2+2*attWidthMpl,e/2+(l-2*e)/2+2*attWidthMpl,-wPlate/2])cube([(l-2*e)/2-w*attWidthMpl*2,(l-2*e)/2-w*attWidthMpl*2,wPlate]);
        
        translate([e/2,e/2+(l-2*e)/2+2*attWidthMpl,-wPlate/2])cube([(l-2*e)/2-w*attWidthMpl*2,(l-2*e)/2-w*attWidthMpl*2,wPlate]);
            
        }
        
        translate([(l/2-17.05/2)-e/2,l/2-e/2,-wPlate/2])
        rotate_extrude(angle=360,convexity=2)
        square([1.8/2,5+wPlate]);
//            cylinder(d=1.8,h=5+wPlate);
            translate([(l/2+17.05/2)-e/2,l/2-e/2,-wPlate/2])
        rotate_extrude(angle=360,convexity=2)
        square([1.8/2,5+wPlate]);
//            cylinder(d=1.8,h=5+wPlate);
    }
    else {
        if (BaseplateCutout) {
            translate([e/2,e/2,-wPlate/2])cube([l-2*e,l-2*e,wPlate]);
        }
        else {
        translate([e/2,e/2,-wPlate/2+w*attWidthMpl])cube([l-2*e,l-2*e,wPlate+w*attWidthMpl]);
        }
    }
    }
    
}

}

module Storey() {

if (!squared) {
        Feder();
        translate([0,l-e,0])Feder();
        rotate([0,0,90])
        translate([0,0,springHeight+wPlate/2])
        Plate();
}
else {
        Feder();
        translate([l-e,0,0])Feder();
        if (SpringRotate) {
            translate([0,l-e,0])rotate([0,0,180])Feder();
            translate([l-e,l-e,0])rotate([0,0,180])Feder();
        }
        else {
            rotate([0,0,180])
            translate([0,l-e,0])Feder();
            rotate([0,0,180])
            translate([l-e,l-e,0])Feder();
        }
        if (BaseplateRotate) {
            translate([0,0,springHeight+wPlate/2])
            rotate([180,0,90])
            Plate();
        }
        else {
            translate([0,0,springHeight+wPlate/2])
        Plate();
        }
}
}
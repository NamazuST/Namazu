module spring(e,w,curve) {
    union() {
        translate([-e/2,0,0])cube([e,e/4,w]);
        translate([e/2,e/4,springCurve+w])
        rotate([0,-90,0])
        rotate_extrude(angle=180, convexity = 2)
        translate([curve,0,0])
        square([w,e]);
        translate([-e/2,0,(springCurve)*2+w])cube([e,e/4,w]);
    }
}

spring(e,w,2);
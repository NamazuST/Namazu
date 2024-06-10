# shakeIt

Available commands:

- **start** - Starts to move the motor to previously specified positions
- **stop** - immediately stops motor movement
- **info** - responds a line of information according the machines state:
`OK: Info: state: READY, mode POSITION, command 25 of 25, rate: 20hz, spmm: 10`

- **set rate nnn.nnn** - set the amout of positions to handle in one second
- **set spmm** - specifies how many steps the motor has to drive to move the carriage one millimeter
- **set mode position/velocity** - changes the interpretation of specified data
- **add nnn.nnn** - adds a position at the end of list
- **reset** - removes all positions from memory

This is an exemplary program to transmit via serial:
```
reset
set spmm 10
set rate 2.5
set mode pos
add 1
add 16
add 20
add 21
add 18
add 0.5
add -20
add -22
add -20
add -10
add 0
start
```

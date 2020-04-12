#!/usr/bin/env python3

import serial
import sys

def WaitForHandshake(ser):
    while True:
        print('.', end='')
        ch = ser.read()
        if ch == b'+':
            return

if len(sys.argv) != 2:
    print('usage: %s file.bin' % sys.argv[0])
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

PORT = '/dev/ttyUSB0'
with serial.Serial(PORT, 9600, timeout=1) as ser:
    print("Waiting for handshake", end='')
    sys.stdout.flush()
    WaitForHandshake(ser)
    ser.write(b'!')

    print('Sending data')
    cksum = 0xffff
    for d in data:
        ch = '%02X' % d
        cksum = (~(cksum + d)) & 0xffff
        ser.write(ch.encode('ascii'))
    ser.write(b'#')

    # send checksum
    ch = '%02X' % (cksum >> 8)
    ser.write(ch.encode('ascii'))
    ch = '%02X' % (cksum & 0xff)
    ser.write(ch.encode('ascii'))

#!/usr/bin/env python3

import binascii
import os
import serial
import select
import struct

class DosScriptClient:
    def __init__(self):
        self._CHUNK_LENGTH = 4096
        self._serial = None
        if False:
            self._fin = os.open('/tmp/serial.out', os.O_RDONLY | os.O_NONBLOCK)
            self._fout = os.open('/tmp/serial.in', os.O_WRONLY)
        else:
            self._serial = serial.Serial('/dev/ttyUSB0', 115200, timeout=1)

    def _receive(self, size=1):
        if self._serial:
            x = bytearray()
            while len(x) < size:
                x += self._serial.read(size)
            return x
        else:
            timeout = None
            select.select([self._fin], [], [self._fin], timeout)
            return os.read(self._fin, 100 + size)

    def _send(self, data):
        if self._serial:
            self._serial.write(data)
        else:
            os.write(self._fout, data)

    def _send_u16(self, value):
        assert value >= 0 and value <= 0xffff
        self._send(struct.pack('!H', value))

    def _send_u32(self, value):
        assert value >= 0 and value <= 0xffffffff
        self._send(struct.pack('!I', value))

    def _send_string(self, s):
        self._send(s.encode('ascii' ) + b'$')

    def handshake(self):
        for _ in range(3):
            self._send(b'#')
        while True:
            x = self._receive()
            if x and x[-1] == ord('?'):
                self._send(b'!')
                return

    def execute(self, prog, args):
        self._send(b'E')
        self._send_string(prog)
        ch = self._receive()
        if not ch or ch[0] != ord('+'):
            print('< Execute rejected: ', ch)
            return False
        self._send(struct.pack('!B', len(args)))
        ch = self._receive()
        if not ch or ch[0] != ord('+'):
            print('< Execute rejected: ', ch)
            return False
        for a in args:
            self._send_string(a)
        ch = self._receive(3)
        if ch and ch[0] != ord('^'):
            print('< Execute failed: ', ch)
            return False
        code, = struct.unpack('!H', ch[1:3])
        print('> Execute yielded return code ', code)
        return True

    def transmit_file(self, fname, data):
        self._send(b'W' + fname.encode('ascii' ) + b'$')
        ch = self._receive()
        if not ch or ch[0] != ord('+'):
            print('< Transmit file rejected: ', ch)
            return False
        self._send_u32(len(data))
        num_sent = 0
        while num_sent < len(data):
            chunk = data[num_sent:num_sent + self._CHUNK_LENGTH]
            checksum = binascii.crc_hqx(chunk, 0)
            self._send(struct.pack('!BHH', ord('c'), len(chunk), checksum))
            self._send(chunk)
            num_sent += len(chunk)

            ch = self._receive()
            print(ch)
            if not ch or ch[0] != ord('+'):
                print('< Transmit chunk rejected: ', ch)
                return False
            ch = ch[1:]
            if ch and ch[0] == ord('^'):
                if num_sent == len(data):
                    return True
                print('< Error: received complete, yet sent only {} bytes of {} total'.format(num_sent, len(data)))
                return False
        ch = self._receive()
        return ch and ch[0] == ord('^')

    def remove_file(self, fname):
        self._send(b'R' + fname.encode('ascii' ) + b'$')
        ch = self._receive()
        if not ch or ch[0] != ord('+'):
            print('< Remove file failed: ', ch)
            return False
        return True


#!/usr/bin/env python3

import os

import client
import recorder

# wait for handshake request
client = client.DosScriptClient()
print('> Waiting for handshake request..')
client.handshake()

print('< Connection established')
#client.transmit_file('FOO.TXT', b'Hello world')
#quit()

#with open('/nfs/retro/PKUNZIP.EXE', 'rb') as f:
#    pk = f.read()
#client.remove_file('P.EXE')
#client.transmit_file('P.EXE', pk)

#client.execute('C:\\COMMAND.COM', [ ])

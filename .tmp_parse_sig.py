import struct, sys, hashlib

APK_SIG_MAGIC = b'APK Sig Block 42'
V2 = 0x7109871a

for path in sys.argv[1:]:
    data = open(path, 'rb').read()
    eocd = data.rfind(b'PK\x05\x06')
    pm = data.rfind(APK_SIG_MAGIC, 0, eocd)
    size2 = struct.unpack_from('<Q', data, pm - 8)[0]
    pair = pm - size2 + 16
    cap = pm - 8
    while pair + 12 <= cap:
        length = struct.unpack_from('<Q', data, pair)[0]
        block_id = struct.unpack_from('<I', data, pair + 8)[0]
        if block_id == V2:
            value = data[pair + 12: pair + 12 + length - 4]
            print(path, 'v2 valuelen=', len(value))
            uu = lambda o: struct.unpack_from('<I', value, o)[0]
            print('  u32[0..6 ]:', [uu(o) for o in (0,4,8,12,16,20,24)])
            print('  head hex :', value[:40].hex())
            # try: length-prefixed sequence: total=value[0:4]; count=value[4:8]
            total = uu(0); cnt = uu(4)
            print('  total=', total, 'cnt=', cnt)
        pair += length - 4 + 12
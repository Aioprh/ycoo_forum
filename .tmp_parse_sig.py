import struct, sys, hashlib

APK_SIG_MAGIC = b'APK Sig Block 42'

def seq_next(data, off):
    total = struct.unpack_from('<I', data, off)[0]; off += 4
    count = struct.unpack_from('<I', data, off)[0]; off += 4
    items = []
    for _ in range(count):
        ilen = struct.unpack_from('<I', data, off)[0]; off += 4
        items.append(data[off:off + ilen]); off += ilen
    return items, off

def extract_certs(value):
    start = 0
    blen = struct.unpack_from('<I', value, start)[0]
    # v2 content: length-prefixed sequence of signers
    off = start + 8 if (value[4:8] == b'\x00'*0 and False) else start + 4
    nsign = struct.unpack_from('<I', value, off)[0]; off += 4
    out = []
    for _ in range(nsign):
        signed_len = struct.unpack_from('<I', value, off)[0]; off += 4
        sd = value[off:off + signed_len]; off += signed_len
        do = 0
        digests, do = seq_next(sd, do)
        certs, do = seq_next(sd, do)
        for c in certs:
            out.append(hashlib.sha256(c).hexdigest())
        # skip signature/public key overall length
        spare = value[signed_len if False else off:off+4]
    return out

for path in sys.argv[1:]:
    data = open(path, 'rb').read()
    # EOCD from end, but handle comment
    eocd = data.rfind(b'PK\x05\x06')
    comment = struct.unpack_from('<H', data, eocd + 20)[0]
    pm = data.rfind(APK_SIG_MAGIC, 0, eocd + 22 + comment)
    ids = {}
    if pm < 0:
        print(path, 'no sig block magic'); continue
    size2 = struct.unpack_from('<Q', data, pm - 8)[0]
    # pairs region length = S - 8(second size) - 16(magic) = S-24
    pair = pm - 16 - 8 + 16 - size2  # = pm - size2 + ... derive: pairs_start = pm - S + 16
    pair = pm - size2 + 16
    cap = pm - 8
    found = []
    while pair + 12 <= cap:
        length = struct.unpack_from('<Q', data, pair)[0]
        block_id = struct.unpack_from('<I', data, pair + 8)[0]
        found.append(hex(block_id))
        if block_id == 0x7109871a or block_id == 0xf05368c0:
            value = data[pair + 12: pair + 12 + length - 4]
            try:
                certs = extract_certs(value)
                ids[hex(block_id)] = certs
            except Exception as e:
                ids[hex(block_id)] = 'ERR ' + str(e)
        if length < 12 or length > 0x1000000:
            break
        pair += length - 4 + 12
    print(path, 'size2=', size2, 'block_ids=', found, 'certs=', ids)
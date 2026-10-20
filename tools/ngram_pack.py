#!/usr/bin/env python3
"""
ngram_pack.py -- Lossless conversion of NGRM v1 dictionaries to the compact v2 layout.

v1 stores every prediction as a 4-byte string offset plus a 2-byte score and needs
an in-memory index built at load. v2 stores the same entries, in the same order, as
mmap-ready tables:

  header (64 bytes)
  key table:    uint32 key hash per entry (bigrams, then trigrams; each section sorted)
  start table:  uint32 first result of each entry, plus one end sentinel
  result table: uint32 per prediction = word index << score_bits | score index
  word table:   uint32 string-table offset per distinct predicted word
  score table:  uint16 per distinct score, ascending
  string table: unchanged null-terminated UTF-8 words

Header (little endian):
  [0..3] "NGRM"  [4..5] version 2  [6..7] score_bits
  [8] bigram_count  [12] trigram_count  [16] key_table_offset  [20] start_table_offset
  [24] result_table_offset  [28] result_count  [32] word_table_offset  [36] word_count
  [40] score_table_offset  [44] score_count  [48] string_table_offset
  [52] string_table_size  [56..63] reserved

Usage:
    python3 tools/ngram_pack.py DictusKeyboard/Resources/*_ngrams.dict   # converts in place
    python3 tools/ngram_pack.py --self-test
"""

import struct
import sys

MAGIC = b"NGRM"
MAX_RESULTS = 16  # Must match NGRM_MAX_RESULTS in dictus_ngram_format.h
V2_HEADER_SIZE = 64


def _string(table, offset):
    end = table.index(b"\0", offset)
    return table[offset:end]


def decode_v1(data):
    """Returns (bigrams, trigrams, string_table); each entry is (hash, [(word_offset, score)])."""
    magic, version, _, bigram_count, trigram_count, bigram_offset, trigram_offset, \
        string_offset, string_size = struct.unpack_from("<4sHHIIIIII", data)
    if magic != MAGIC or version != 1:
        raise ValueError("Not an NGRM v1 file")

    def section(offset, count):
        entries = []
        for _ in range(count):
            key_hash, result_count = struct.unpack_from("<IB", data, offset)
            offset += 5
            results = list(struct.iter_unpack("<IH", data[offset:offset + 6 * result_count]))
            offset += 6 * result_count
            entries.append((key_hash, results))
        return entries, offset

    bigrams, end = section(bigram_offset, bigram_count)
    if end != trigram_offset:
        raise ValueError("Bigram section does not end at the trigram section")
    trigrams, end = section(trigram_offset, trigram_count)
    if end != string_offset or string_offset + string_size != len(data):
        raise ValueError("Unexpected v1 section layout")
    return bigrams, trigrams, bytes(data[string_offset:string_offset + string_size])


def encode_v2(bigrams, trigrams, string_table):
    entries = bigrams + trigrams
    word_offsets = sorted({offset for _, results in entries for offset, _ in results})
    scores = sorted({score for _, results in entries for _, score in results})
    word_index = {offset: index for index, offset in enumerate(word_offsets)}
    score_index = {score: index for index, score in enumerate(scores)}
    score_bits = max(1, (len(scores) - 1).bit_length())
    if len(word_offsets) > 1 << (32 - score_bits):
        raise ValueError("Too many distinct words and scores for 32-bit results")
    if any(len(results) > MAX_RESULTS for _, results in entries):
        raise ValueError("An entry exceeds the result cap")
    for offset in word_offsets:
        _string(string_table, offset)  # every referenced word must be terminated

    keys = struct.pack(f"<{len(entries)}I", *(key_hash for key_hash, _ in entries))
    starts, results, position = [], [], 0
    for _, entry_results in entries:
        starts.append(position)
        for offset, score in entry_results:
            results.append(word_index[offset] << score_bits | score_index[score])
        position += len(entry_results)
    starts.append(position)

    tables = [
        keys,
        struct.pack(f"<{len(starts)}I", *starts),
        struct.pack(f"<{len(results)}I", *results),
        struct.pack(f"<{len(word_offsets)}I", *word_offsets),
        struct.pack(f"<{len(scores)}H", *scores),
    ]
    offsets, cursor = [], V2_HEADER_SIZE
    for table in tables:
        offsets.append(cursor)
        cursor += len(table) + (-len(table) % 4)
    string_offset = cursor

    header = struct.pack(
        "<4sHHIIIIIIIIIIII8x", MAGIC, 2, score_bits, len(bigrams), len(trigrams),
        offsets[0], offsets[1], offsets[2], len(results), offsets[3], len(word_offsets),
        offsets[4], len(scores), string_offset, len(string_table))
    body = b"".join(table + b"\0" * (-len(table) % 4) for table in tables)
    return header + body + string_table


def decode_v2(data):
    """Returns (bigrams, trigrams, string_table) with entries as (hash, [(word, score)])."""
    (magic, version, score_bits, bigram_count, trigram_count, key_offset, start_offset,
     result_offset, result_count, word_offset, word_count, score_offset, score_count,
     string_offset, string_size) = struct.unpack_from("<4sHHIIIIIIIIIIII", data)
    if magic != MAGIC or version != 2 or string_offset + string_size != len(data):
        raise ValueError("Not a well-formed NGRM v2 file")
    count = bigram_count + trigram_count
    keys = struct.unpack_from(f"<{count}I", data, key_offset)
    starts = struct.unpack_from(f"<{count + 1}I", data, start_offset)
    results = struct.unpack_from(f"<{result_count}I", data, result_offset)
    words = struct.unpack_from(f"<{word_count}I", data, word_offset)
    scores = struct.unpack_from(f"<{score_count}H", data, score_offset)
    strings = bytes(data[string_offset:])
    mask = (1 << score_bits) - 1
    entries = [(keys[i], [(_string(strings, words[packed >> score_bits]), scores[packed & mask])
                          for packed in results[starts[i]:starts[i + 1]]]) for i in range(count)]
    return entries[:bigram_count], entries[bigram_count:], strings


def with_words(entries, string_table):
    return [(key_hash, [(_string(string_table, offset), score) for offset, score in results])
            for key_hash, results in entries]


def convert(data):
    """Converts v1 bytes to v2 bytes and proves the round trip is lossless."""
    bigrams, trigrams, strings = decode_v1(data)
    packed = encode_v2(bigrams, trigrams, strings)
    back_bigrams, back_trigrams, _ = decode_v2(packed)
    if back_bigrams != with_words(bigrams, strings) or back_trigrams != with_words(trigrams, strings):
        raise ValueError("v2 round trip changed an entry")
    return packed


def self_test():
    strings = b"de\0le\0la\0"
    bigrams = [(7, [(0, 900), (3, 40)]), (7, [(6, 65535)]), (90, [])]
    trigrams = [(5, [(3, 40), (0, 0)] + [(6, 12)] * 14)]

    def section(entries):
        return b"".join(struct.pack("<IB", h, len(r)) + b"".join(struct.pack("<IH", *x) for x in r)
                        for h, r in entries)
    bigram_bytes, trigram_bytes = section(bigrams), section(trigrams)
    header = struct.pack("<4sHHIIIIII", MAGIC, 1, 0, len(bigrams), len(trigrams), 32,
                         32 + len(bigram_bytes), 32 + len(bigram_bytes) + len(trigram_bytes), len(strings))
    v1 = header + bigram_bytes + trigram_bytes + strings
    v2 = convert(v1)
    decoded = decode_v2(v2)
    assert decoded[0][1] == (7, [(b"la", 65535)]) and decoded[1][0][1][1] == (b"de", 0)
    assert len(v2) % 4 == len(strings) % 4
    try:
        encode_v2([(1, [(0, 1)] * (MAX_RESULTS + 1))], [], strings)
        raise AssertionError("over-long entry accepted")
    except ValueError:
        pass
    print("ngram_pack self-test passed")


def main(paths):
    if paths == ["--self-test"]:
        self_test()
        return
    for path in paths:
        with open(path, "rb") as handle:
            data = handle.read()
        if data[4:6] == struct.pack("<H", 2):
            print(f"{path}: already v2 ({len(data)} bytes)")
            continue
        packed = convert(data)
        with open(path, "wb") as handle:
            handle.write(packed)
        print(f"{path}: {len(data)} -> {len(packed)} bytes")


if __name__ == "__main__":
    main(sys.argv[1:])

// N-gram binary format for Dictus next-word prediction. Apache 2.0.
#ifndef DICTUS_NGRAM_FORMAT_H
#define DICTUS_NGRAM_FORMAT_H

#include <cstdint>

namespace dictus {

/// Magic bytes identifying an NGRM binary file.
static constexpr char NGRM_MAGIC[4] = {'N', 'G', 'R', 'M'};

/// Current format version. Version 1 files are converted with tools/ngram_pack.py.
static constexpr uint16_t NGRM_VERSION = 2;

/// Maximum number of prediction results stored per n-gram key.
/// Increased from 8 to 16 to accommodate both formal Wikipedia pairs and
/// colloquial seed bigrams (e.g., "pas" has ~8 formal pairs from Wikipedia
/// plus ~13 colloquial seeds — "pas mal", "pas du", etc. — that need to
/// survive the cap to unlock split validation in the keyboard).
static constexpr uint8_t NGRM_MAX_RESULTS = 16;

/// Header size in bytes.
static constexpr uint32_t NGRM_HEADER_SIZE = 64;

/// NGRM v2 file header (64 bytes, little endian).
///
/// Every table is mmap-ready, so loading builds no index:
///   key table:    uint32 FNV-1a key hash per entry — bigram entries first, then
///                 trigram entries; each section sorted by hash ascending
///   start table:  uint32 index of each entry's first result, plus one end sentinel
///   result table: uint32 per prediction = word_index << score_bits | score_index,
///                 in descending score order within an entry
///   word table:   uint32 string-table offset per distinct predicted word
///   score table:  uint16 per distinct score (log-scaled 0..65535)
///   string table: packed null-terminated UTF-8 words
///
/// Bigram key = lowercase previous word (UTF-8 bytes).
/// Trigram key = "word1\0word2" (null-separated, both lowercase, UTF-8 bytes).
#pragma pack(push, 1)
struct NgramHeader {
    char magic[4];                // "NGRM"
    uint16_t version;             // 2
    uint16_t score_bits;          // low bits of a result holding its score index
    uint32_t bigram_count;
    uint32_t trigram_count;
    uint32_t key_table_offset;
    uint32_t start_table_offset;
    uint32_t result_table_offset;
    uint32_t result_count;
    uint32_t word_table_offset;
    uint32_t word_count;
    uint32_t score_table_offset;
    uint32_t score_count;
    uint32_t string_table_offset;
    uint32_t string_table_size;
    uint8_t reserved[8];
};
#pragma pack(pop)

static_assert(sizeof(NgramHeader) == NGRM_HEADER_SIZE, "NgramHeader must be exactly 64 bytes");

} // namespace dictus

#endif // DICTUS_NGRAM_FORMAT_H

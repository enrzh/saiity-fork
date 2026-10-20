// N-gram prediction engine for Dictus. Apache 2.0.
#include "dictus_ngram.h"
#include "dictus_ngram_format.h"

#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace dictus {

namespace {

uint32_t read32(const uint8_t* table, uint32_t index) {
    uint32_t value;
    std::memcpy(&value, table + static_cast<size_t>(index) * 4, 4);
    return value;
}

uint16_t read16(const uint8_t* table, uint32_t index) {
    uint16_t value;
    std::memcpy(&value, table + static_cast<size_t>(index) * 2, 2);
    return value;
}

bool fits(uint64_t offset, uint64_t length, uint64_t fileSize) {
    return offset <= fileSize && length <= fileSize - offset;
}

} // namespace

// --- Constructor / Destructor ---

NgramEngine::NgramEngine() : data_(nullptr), dataSize_(0), loaded_(false) {}

NgramEngine::~NgramEngine() {
    unload();
}

// --- Load / Unload ---

bool NgramEngine::load(const char* path) {
    unload();

    int fd = open(path, O_RDONLY);
    if (fd < 0) return false;

    struct stat st;
    if (fstat(fd, &st) != 0) {
        close(fd);
        return false;
    }

    size_t fileSize = static_cast<size_t>(st.st_size);
    if (fileSize < NGRM_HEADER_SIZE) {
        close(fd);
        return false;
    }

    void* mapped = mmap(nullptr, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);

    if (mapped == MAP_FAILED) {
        return false;
    }

    madvise(mapped, fileSize, MADV_RANDOM);

    data_ = static_cast<uint8_t*>(mapped);
    dataSize_ = fileSize;

    // Validate header
    NgramHeader hdr;
    std::memcpy(&hdr, data_, sizeof(hdr));
    if (std::memcmp(hdr.magic, NGRM_MAGIC, 4) != 0 || hdr.version != NGRM_VERSION ||
        hdr.score_bits == 0 || hdr.score_bits > 31) {
        unload();
        return false;
    }

    // Validate that every table lies within the file
    uint64_t entries = static_cast<uint64_t>(hdr.bigram_count) + hdr.trigram_count;
    if (!fits(hdr.key_table_offset, entries * 4, fileSize) ||
        !fits(hdr.start_table_offset, (entries + 1) * 4, fileSize) ||
        !fits(hdr.result_table_offset, static_cast<uint64_t>(hdr.result_count) * 4, fileSize) ||
        !fits(hdr.word_table_offset, static_cast<uint64_t>(hdr.word_count) * 4, fileSize) ||
        !fits(hdr.score_table_offset, static_cast<uint64_t>(hdr.score_count) * 2, fileSize) ||
        !fits(hdr.string_table_offset, hdr.string_table_size, fileSize)) {
        unload();
        return false;
    }

    // Every word must be terminated inside the string table
    if (hdr.string_table_size > 0 &&
        data_[hdr.string_table_offset + hdr.string_table_size - 1] != '\0') {
        unload();
        return false;
    }

    bigramCount_ = hdr.bigram_count;
    trigramCount_ = hdr.trigram_count;
    keys_ = data_ + hdr.key_table_offset;
    starts_ = data_ + hdr.start_table_offset;
    results_ = data_ + hdr.result_table_offset;
    resultCount_ = hdr.result_count;
    words_ = data_ + hdr.word_table_offset;
    wordCount_ = hdr.word_count;
    scores_ = data_ + hdr.score_table_offset;
    scoreCount_ = hdr.score_count;
    scoreBits_ = hdr.score_bits;
    strings_ = reinterpret_cast<const char*>(data_ + hdr.string_table_offset);
    stringsSize_ = hdr.string_table_size;

    loaded_ = true;
    return true;
}

void NgramEngine::unload() {
    if (data_) {
        munmap(data_, dataSize_);
        data_ = nullptr;
    }
    dataSize_ = 0;
    bigramCount_ = 0;
    trigramCount_ = 0;
    keys_ = starts_ = results_ = words_ = scores_ = nullptr;
    resultCount_ = wordCount_ = scoreCount_ = stringsSize_ = 0;
    scoreBits_ = 0;
    strings_ = nullptr;
    loaded_ = false;
}

bool NgramEngine::isLoaded() const {
    return loaded_;
}

// --- FNV-1a hash ---

uint32_t NgramEngine::fnv1a(const uint8_t* bytes, size_t len) {
    uint32_t h = 0x811c9dc5;
    for (size_t i = 0; i < len; i++) {
        h ^= bytes[i];
        h *= 0x01000193;
    }
    return h;
}

// --- Lowercase utility ---

size_t NgramEngine::toLower(const char* input, char* output, size_t maxLen) {
    size_t len = 0;
    while (input[len] != '\0' && len < maxLen - 1) {
        char c = input[len];
        // ASCII lowercase only (n-gram keys are already normalized in binary)
        if (c >= 'A' && c <= 'Z') {
            output[len] = c + ('a' - 'A');
        } else {
            output[len] = c;
        }
        len++;
    }
    output[len] = '\0';
    return len;
}

// --- Binary search ---

int64_t NgramEngine::findEntry(uint32_t keyHash, uint32_t first, uint32_t count) const {
    // Binary search on sorted key hashes
    size_t lo = 0;
    size_t hi = count;

    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        uint32_t midHash = read32(keys_, first + static_cast<uint32_t>(mid));
        if (midHash < keyHash) {
            lo = mid + 1;
        } else if (midHash > keyHash) {
            hi = mid;
        } else {
            return static_cast<int64_t>(first) + static_cast<int64_t>(mid);
        }
    }
    return kNoEntry;
}

// --- Results ---

size_t NgramEngine::resultCount(int64_t entry, uint32_t* firstResult) const {
    if (entry == kNoEntry) return 0;

    uint32_t start = read32(starts_, static_cast<uint32_t>(entry));
    uint32_t end = read32(starts_, static_cast<uint32_t>(entry) + 1);
    if (start > end || end > resultCount_) return 0;

    *firstResult = start;
    return std::min(static_cast<size_t>(end - start), static_cast<size_t>(NGRM_MAX_RESULTS));
}

bool NgramEngine::resultAt(uint32_t resultIndex, const char** word, uint16_t* score) const {
    uint32_t packed = read32(results_, resultIndex);
    uint32_t wordIndex = packed >> scoreBits_;
    uint32_t scoreIndex = packed & ((1u << scoreBits_) - 1);
    if (wordIndex >= wordCount_ || scoreIndex >= scoreCount_) return false;

    uint32_t offset = read32(words_, wordIndex);
    if (offset >= stringsSize_) return false;

    *word = strings_ + offset;
    *score = read16(scores_, scoreIndex);
    return true;
}

std::vector<NgramResult> NgramEngine::parseResults(int64_t entry, size_t maxResults) const {
    std::vector<NgramResult> results;
    uint32_t first = 0;
    size_t count = resultCount(entry, &first);

    size_t limit = std::min(count, maxResults);
    results.reserve(limit);

    for (size_t i = 0; i < limit; i++) {
        NgramResult r;
        const char* word;
        if (resultAt(first + static_cast<uint32_t>(i), &word, &r.score)) {
            r.word = word;
            results.push_back(std::move(r));
        }
    }

    return results;
}

uint16_t NgramEngine::scoreInEntry(int64_t entry, const char* word) const {
    uint32_t first = 0;
    size_t count = resultCount(entry, &first);

    for (size_t i = 0; i < count; i++) {
        const char* candidate;
        uint16_t score;
        if (resultAt(first + static_cast<uint32_t>(i), &candidate, &score) &&
            std::strcmp(candidate, word) == 0) {
            return score;
        }
    }

    return 0;
}

// --- Prediction API ---

std::vector<NgramResult> NgramEngine::predictAfterWord(const char* word,
                                                        size_t maxResults) const {
    if (!loaded_ || !word) return {};

    // Lowercase the input word
    char lowBuf[256];
    size_t len = toLower(word, lowBuf, sizeof(lowBuf));
    if (len == 0) return {};

    // Hash and look up among bigram entries
    uint32_t keyHash = fnv1a(reinterpret_cast<const uint8_t*>(lowBuf), len);
    return parseResults(findEntry(keyHash, 0, bigramCount_), maxResults);
}

std::vector<NgramResult> NgramEngine::predictAfterWords(const char* word1,
                                                         const char* word2,
                                                         size_t maxResults) const {
    if (!loaded_ || !word1 || !word2) return {};

    // Lowercase both words
    char low1[256], low2[256];
    size_t len1 = toLower(word1, low1, sizeof(low1));
    size_t len2 = toLower(word2, low2, sizeof(low2));
    if (len1 == 0 || len2 == 0) return {};

    // Build trigram key: "word1\0word2" (null byte separator)
    char trigramKey[512];
    if (len1 + 1 + len2 > sizeof(trigramKey)) return {};
    std::memcpy(trigramKey, low1, len1);
    trigramKey[len1] = '\0';
    std::memcpy(trigramKey + len1 + 1, low2, len2);
    size_t trigramKeyLen = len1 + 1 + len2;

    uint32_t trigramHash = fnv1a(reinterpret_cast<const uint8_t*>(trigramKey), trigramKeyLen);
    int64_t trigramEntry = findEntry(trigramHash, bigramCount_, trigramCount_);

    // Try bigram for word2 as well (for Stupid Backoff)
    uint32_t bigramHash = fnv1a(reinterpret_cast<const uint8_t*>(low2), len2);
    int64_t bigramEntry = findEntry(bigramHash, 0, bigramCount_);

    if (trigramEntry != kNoEntry && bigramEntry != kNoEntry) {
        // Both found: merge trigram results with discounted bigram results
        auto trigramResults = parseResults(trigramEntry, NGRM_MAX_RESULTS);
        auto bigramResults = parseResults(bigramEntry, NGRM_MAX_RESULTS);

        // Apply Stupid Backoff discount (lambda = 0.4) to bigram scores
        for (auto& r : bigramResults) {
            r.score = static_cast<uint16_t>(static_cast<uint32_t>(r.score) * 4 / 10);
        }

        // Merge: trigram results take priority for same word
        std::vector<NgramResult> merged;
        merged.reserve(trigramResults.size() + bigramResults.size());
        merged.insert(merged.end(), trigramResults.begin(), trigramResults.end());

        // Add bigram results that don't duplicate trigram words
        for (const auto& br : bigramResults) {
            bool duplicate = false;
            for (const auto& tr : trigramResults) {
                if (tr.word == br.word) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) {
                merged.push_back(br);
            }
        }

        // Sort by score descending
        std::sort(merged.begin(), merged.end(),
                  [](const NgramResult& a, const NgramResult& b) {
                      return a.score > b.score;
                  });

        // Cap to maxResults
        if (merged.size() > maxResults) {
            merged.resize(maxResults);
        }
        return merged;

    } else if (trigramEntry != kNoEntry) {
        // Only trigram found
        return parseResults(trigramEntry, maxResults);

    } else if (bigramEntry != kNoEntry) {
        // Fallback to bigram with Stupid Backoff discount
        auto results = parseResults(bigramEntry, maxResults);
        for (auto& r : results) {
            r.score = static_cast<uint16_t>(static_cast<uint32_t>(r.score) * 4 / 10);
        }
        return results;

    }

    return {};
}

// --- Scoring API ---

uint16_t NgramEngine::bigramScore(const char* prevWord, const char* word) const {
    if (!loaded_ || !prevWord || !word) return 0;

    char lowPrev[256];
    size_t prevLen = toLower(prevWord, lowPrev, sizeof(lowPrev));
    if (prevLen == 0) return 0;

    uint32_t keyHash = fnv1a(reinterpret_cast<const uint8_t*>(lowPrev), prevLen);
    int64_t entry = findEntry(keyHash, 0, bigramCount_);
    if (entry == kNoEntry) return 0;

    // Lowercase target word for comparison
    char lowWord[256];
    toLower(word, lowWord, sizeof(lowWord));
    return scoreInEntry(entry, lowWord);
}

uint16_t NgramEngine::trigramScore(const char* word1, const char* word2,
                                    const char* word) const {
    if (!loaded_ || !word1 || !word2 || !word) return 0;

    char low1[256], low2[256];
    size_t len1 = toLower(word1, low1, sizeof(low1));
    size_t len2 = toLower(word2, low2, sizeof(low2));
    if (len1 == 0 || len2 == 0) return 0;

    // Build trigram key
    char trigramKey[512];
    if (len1 + 1 + len2 > sizeof(trigramKey)) return 0;
    std::memcpy(trigramKey, low1, len1);
    trigramKey[len1] = '\0';
    std::memcpy(trigramKey + len1 + 1, low2, len2);
    size_t trigramKeyLen = len1 + 1 + len2;

    uint32_t keyHash = fnv1a(reinterpret_cast<const uint8_t*>(trigramKey), trigramKeyLen);
    int64_t entry = findEntry(keyHash, bigramCount_, trigramCount_);
    if (entry == kNoEntry) return 0;

    // Lowercase target word
    char lowWord[256];
    toLower(word, lowWord, sizeof(lowWord));
    return scoreInEntry(entry, lowWord);
}

} // namespace dictus

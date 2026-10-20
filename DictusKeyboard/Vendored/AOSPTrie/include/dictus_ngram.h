// N-gram prediction engine for Dictus. Apache 2.0.
#ifndef DICTUS_NGRAM_H
#define DICTUS_NGRAM_H

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

namespace dictus {

/// Result from n-gram prediction: a word and its score.
struct NgramResult {
    std::string word;
    uint16_t score;
};

/// N-gram lookup engine using mmap'd binary data (NGRM format).
/// Supports bigram and trigram lookup with Stupid Backoff scoring.
class NgramEngine {
public:
    NgramEngine();
    ~NgramEngine();

    // Non-copyable
    NgramEngine(const NgramEngine&) = delete;
    NgramEngine& operator=(const NgramEngine&) = delete;

    /// Load n-gram binary file via mmap. Returns true on success.
    bool load(const char* path);

    /// Unload mmap'd data and release resources.
    void unload();

    /// Whether data is currently loaded.
    bool isLoaded() const;

    /// Predict top-N next words given one previous word (bigram lookup).
    /// Returns results sorted by score descending, up to maxResults.
    std::vector<NgramResult> predictAfterWord(const char* word, size_t maxResults) const;

    /// Predict top-N next words given two previous words (trigram + bigram backoff).
    /// Uses Stupid Backoff: try trigram first, then bigram with lambda=0.4 discount.
    /// Returns merged results sorted by score descending, up to maxResults.
    std::vector<NgramResult> predictAfterWords(const char* word1, const char* word2, size_t maxResults) const;

    /// Get n-gram score for a specific word following one previous word.
    /// Used for correction boosting. Returns 0 if no match.
    uint16_t bigramScore(const char* prevWord, const char* word) const;

    /// Get n-gram score for a specific word following two previous words.
    /// Returns 0 if no match.
    uint16_t trigramScore(const char* word1, const char* word2, const char* word) const;

private:
    uint8_t* data_;
    size_t dataSize_;
    bool loaded_;

    /// Tables inside the mapped file (see dictus_ngram_format.h).
    uint32_t bigramCount_ = 0;
    uint32_t trigramCount_ = 0;
    const uint8_t* keys_ = nullptr;
    const uint8_t* starts_ = nullptr;
    const uint8_t* results_ = nullptr;
    uint32_t resultCount_ = 0;
    const uint8_t* words_ = nullptr;
    uint32_t wordCount_ = 0;
    const uint8_t* scores_ = nullptr;
    uint32_t scoreCount_ = 0;
    uint16_t scoreBits_ = 0;
    const char* strings_ = nullptr;
    uint32_t stringsSize_ = 0;

    static constexpr int64_t kNoEntry = -1;

    /// FNV-1a 32-bit hash (must match Python implementation exactly).
    static uint32_t fnv1a(const uint8_t* bytes, size_t len);

    /// Lowercase a C string into a stack buffer. Returns length.
    static size_t toLower(const char* input, char* output, size_t maxLen);

    /// Binary search for a key hash among `count` entries starting at `first`.
    /// Returns the entry index, or kNoEntry.
    int64_t findEntry(uint32_t keyHash, uint32_t first, uint32_t count) const;

    /// Stored results of an entry (capped at NGRM_MAX_RESULTS) and the first one's index.
    size_t resultCount(int64_t entry, uint32_t* firstResult) const;

    /// Word and score of one stored result. Returns false for an invalid result.
    bool resultAt(uint32_t resultIndex, const char** word, uint16_t* score) const;

    /// Parse results of an entry into NgramResult vector.
    std::vector<NgramResult> parseResults(int64_t entry, size_t maxResults) const;

    /// Score of `word` among an entry's results, or 0.
    uint16_t scoreInEntry(int64_t entry, const char* word) const;
};

} // namespace dictus

#endif // DICTUS_NGRAM_H

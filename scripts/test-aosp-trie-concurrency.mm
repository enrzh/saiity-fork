// Compile from the repo root with xcrun clang++ -std=c++17 -fobjc-arc -g -O1
// -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation
// -IDictusKeyboard/Vendored/AOSPTrie/include -IDictusKeyboard/Vendored/AOSPTrie/bridge
// scripts/test-aosp-trie-concurrency.mm DictusKeyboard/Vendored/AOSPTrie/bridge/AOSPTrieBridge.mm
// DictusKeyboard/Vendored/AOSPTrie/src/*.cpp -o /tmp/test-aosp-trie-concurrency
// Run the resulting binary from the repo root. Use -fsanitize=thread separately.
#import "AOSPTrieBridge.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <thread>

int main() {
    @autoreleasepool {
        AOSPTrieBridge *bridge = [[AOSPTrieBridge alloc] init];
        NSArray<NSString *> *languages = @[@"en", @"fr", @"de", @"es"];
        NSString *(^path)(NSString *, NSString *) = ^(NSString *language, NSString *kind) {
            return [NSString stringWithFormat:@"DictusKeyboard/Resources/%@_%@.dict", language, kind];
        };
        assert([bridge loadDictionaryAtPath:path(@"en", @"spellcheck")]);
        assert([bridge loadNgramsAtPath:path(@"en", @"ngrams")]);
        assert([bridge wordExists:@"hello"]);
        assert([bridge predictAfterWord:@"i" maxResults:3].count > 0);
        assert([bridge predictAfterWord1:@"i" word2:@"am" maxResults:3].count > 0);

        std::atomic<bool> start{false}, finished{false};
        std::atomic<size_t> reads{0};
        auto reader = [&] {
            while (!start.load()) std::this_thread::yield();
            for (size_t i = 0; !finished.load() || i < 2000; ++i) {
                @autoreleasepool {
                    [bridge predictAfterWord:@"i" maxResults:3];
                    [bridge predictAfterWord1:@"i" word2:@"am" maxResults:3];
                    [bridge bigramScoreForWord:@"am" afterWord:@"i"];
                    [bridge wordExists:@"hello"];
                    [bridge getFrequency:@"hello"];
                    [bridge wordCount];
                    [bridge isLoaded];
                    [bridge ngramsLoaded];
                    if (i % 20 == 0) {
                        [bridge spellCheck:@"helo" maxEditDistance:1];
                        [bridge nearbyWords:@"hello" maxEditDistance:1 maxResults:3];
                    }
                    reads.fetch_add(1);
                }
            }
        };
        std::thread first(reader), second(reader);
        std::thread loader([&] {
            while (!start.load()) std::this_thread::yield();
            for (size_t i = 0; i < 80; ++i) {
                @autoreleasepool {
                    NSString *language = languages[i % languages.count];
                    [bridge unloadDictionary];
                    [bridge unloadNgrams];
                    assert([bridge loadDictionaryAtPath:path(language, @"spellcheck")]);
                    assert([bridge loadNgramsAtPath:path(language, @"ngrams")]);
                    uint16_t characters[] = {'h', 'e'};
                    float distances[] = {0, 1, 1, 0}, costs[] = {0.5f};
                    NSData *chars = [NSData dataWithBytes:characters length:sizeof(characters)];
                    assert([bridge setProximityTableWithCharacters:chars
                        distances:[NSData dataWithBytes:distances length:sizeof(distances)]]);
                    assert([bridge setAccentCostsFrom:[NSData dataWithBytes:characters length:2]
                        to:[NSData dataWithBytes:characters + 1 length:2]
                        costs:[NSData dataWithBytes:costs length:sizeof(costs)]]);
                }
            }
            finished.store(true);
        });
        start.store(true);
        loader.join();
        first.join();
        second.join();

        // Failed loads and teardown leave every lookup safe and empty.
        assert(![bridge loadDictionaryAtPath:@"/missing/saiity-spellcheck.dict"]);
        assert(![bridge loadNgramsAtPath:@"/missing/saiity-ngrams.dict"]);
        assert(![bridge isLoaded] && ![bridge ngramsLoaded]);
        assert([bridge predictAfterWord:@"i" maxResults:3].count == 0);
        assert([bridge predictAfterWord1:@"i" word2:@"am" maxResults:3].count == 0);
        assert([bridge spellCheck:@"helo" maxEditDistance:1] == nil);
        assert(![bridge wordExists:@"hello"]);
        printf("PASS: %zu concurrent prediction/spelling reads across 80 language reloads and teardown\n", reads.load());
    }
}

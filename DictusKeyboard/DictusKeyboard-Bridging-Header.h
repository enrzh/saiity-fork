// DictusKeyboard-Bridging-Header.h
// Bridges ObjC++ types to Swift for the DictusKeyboard target.
#import "AOSPTrieBridge.h"
#import <UIKit/UIKit.h>

// UIKit can return nil before its host document is attached. Keep that optional
// at the ObjC boundary instead of bridging it into Swift's non-optional UUID.
NS_INLINE NSUUID * _Nullable DictusNullableDocumentIdentifier(id<UITextDocumentProxy> _Nullable proxy) {
    return [proxy documentIdentifier];
}

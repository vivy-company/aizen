//
//  ghostty-bridging-header.h
//  aizen
//
//  Bridging header to expose Ghostty C API to Swift
//

#ifndef ghostty_bridging_header_h
#define ghostty_bridging_header_h

// Import the main Ghostty C API
// Note: ghostty.h already includes all necessary definitions
// Do NOT include ghostty/vt.h as it causes duplicate enum definitions
#import "../libghostty/include/ghostty.h"

#endif /* ghostty_bridging_header_h */

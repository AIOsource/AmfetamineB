//
//  Amfeta-Spoit-Bridging-Header.h
//  Amfeta-Spoit
//

#ifndef Amfeta_Spoit_Bridging_Header_h
#define Amfeta_Spoit_Bridging_Header_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GrappaHelper.h"
#import "xpc_crash.h"
#import "bad_query.h"

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (bool)openApplicationWithBundleID:(NSString*)bundleID;
@end

#endif /* Amfeta_Spoit_Bridging_Header_h */

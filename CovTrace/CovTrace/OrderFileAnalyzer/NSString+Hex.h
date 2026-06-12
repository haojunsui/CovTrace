#import <Foundation/Foundation.h>

@interface NSString (Hex)

- (unsigned long long)decimalFromHex;

+ (NSString *)hexFromDecimal:(unsigned long long)decimal;

@end

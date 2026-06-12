#import "NSString+Hex.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (Hex)

- (unsigned long long)decimalFromHex {
	unsigned long long result = 0;
	NSScanner *scanner = [NSScanner scannerWithString:self];
	[scanner scanHexLongLong:&result];

	return result;
}

+ (NSString *)hexFromDecimal:(unsigned long long)decimal {
	return [NSString stringWithFormat:@"0x%llX", decimal];
}

@end

NS_ASSUME_NONNULL_END

#import "Linkmap.h"
#import "NSString+Hex.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Linkmap

- (instancetype)initWithContent:(NSString *)content {
	self = [super init];
	if (self) {
		_content = content;
		_sections = [LinkmapSections dictionary];
		_symbolNameToAddressMap = [NSMutableDictionary dictionary];
		_duplicatedSymbols = [NSMutableArray array];
		_addressJumpedSymbols = [NSMutableArray array];

		[self process];
	}
	return self;
}

- (void)process {
	[self processSections];
	[self processSymbols];
}

- (nullable SymbolAddress *)symbolAddressForSegment:(NSString *)segment section:(NSString *)section {
	NSDictionary *segments = [_sections objectForKey:segment];
	if (segments == nil) {
		return nil;
	}
	return [segments objectForKey:section];
}

- (void)processSections {
	// Example of linkmap sections
	// # Address    Size        Segment    Section
	// 0x00001558    0x00041E60    __TEXT    __text
	// 0x00054D88    0x00001A00    __DATA_CONST    __const
	// 0x0005CFE0    0x00001B80    __DATA    __data
	NSRegularExpression *regexLinkmapSectionText = [NSRegularExpression
	    regularExpressionWithPattern:@"(0x[A-F\\d]*)\\s+(0x[A-F\\d]*)\\s+__(\\w+)\\s+__(\\w+)"
	                         options:0
	                           error:nil];
	[regexLinkmapSectionText enumerateMatchesInString:_content
	                                          options:0
	                                            range:NSMakeRange(0, [_content length])
	                                       usingBlock:^(NSTextCheckingResult *_Nullable result, __unused NSMatchingFlags flags, __unused BOOL *_Nonnull stop) {
		                                       if ([result numberOfRanges] != 5)
			                                       return;

		                                       NSString *sectionTextStartAddressHexStr = [_content substringWithRange:[result rangeAtIndex:1]];
		                                       NSString *sectionTextSizeHexStr = [_content substringWithRange:[result rangeAtIndex:2]];
		                                       SymbolAddress *sectionAddress = [[SymbolAddress alloc] initWithStartAddress:[sectionTextStartAddressHexStr decimalFromHex] size:[sectionTextSizeHexStr decimalFromHex]];

		                                       NSString *segment = [_content substringWithRange:[result rangeAtIndex:3]];
		                                       NSString *section = [_content substringWithRange:[result rangeAtIndex:4]];

		                                       if ([_sections objectForKey:segment] == nil) {
			                                       [_sections setObject:[NSMutableDictionary dictionary] forKey:segment];
		                                       }
		                                       [[_sections objectForKey:segment] setObject:sectionAddress forKey:section];
	                                       }];
}

- (void)processSymbols {
	// Read symbols from linkmap file
	// # Address    Size        File  Name
	// 0x00000000    0x00000000    [  0] foo
	// 0x00001558    0x0000006C    [  9] bar

	// Gather info on address jumped symbols in linkmap
	// __Text symbol start + size != next start
	__block unsigned long long expectedNextSymbolStartAddressDecimalValue = 0;

	NSRegularExpression *regexLinkmapSymbol = [NSRegularExpression
	    regularExpressionWithPattern:@"(0x[A-F\\d]*)\\s+(0x[A-F\\d]*)\\s+\\[.*\\]\\s(.+)"
	                         options:0
	                           error:nil];
	[regexLinkmapSymbol enumerateMatchesInString:_content
	                                     options:0
	                                       range:NSMakeRange(0, [_content length])
	                                  usingBlock:^(NSTextCheckingResult *_Nullable result, __unused NSMatchingFlags flags, __unused BOOL *_Nonnull stop) {
		                                  if ([result numberOfRanges] != 4)
			                                  return;

		                                  NSString *symbolStartAddressHexStr = [_content substringWithRange:[result rangeAtIndex:1]];
		                                  unsigned long long symbolStartAddressDecimalValue = [symbolStartAddressHexStr decimalFromHex];

		                                  NSString *symbolSizeHexStr = [_content substringWithRange:[result rangeAtIndex:2]];
		                                  unsigned long long symbolSizeDecimalValue = [symbolSizeHexStr decimalFromHex];

		                                  NSString *symbolName = [_content substringWithRange:[result rangeAtIndex:3]];

		                                  SymbolAddress *symbolAddress = [[SymbolAddress alloc] initWithStartAddress:symbolStartAddressDecimalValue size:symbolSizeDecimalValue];

		                                  // Filter all symbols that is not within __TEXT __text section
		                                  SymbolAddress *sectionTextAddress = [self symbolAddressForSegment:@"TEXT" section:@"text"];

		                                  if (symbolStartAddressDecimalValue >= [sectionTextAddress start] && symbolStartAddressDecimalValue < ([sectionTextAddress start] + [sectionTextAddress size])) {
			                                  if (symbolSizeDecimalValue != 0) {
				                                  if (expectedNextSymbolStartAddressDecimalValue != 0 && expectedNextSymbolStartAddressDecimalValue != symbolStartAddressDecimalValue) {
					                                  [_addressJumpedSymbols addObject:symbolAddress];
				                                  }
				                                  expectedNextSymbolStartAddressDecimalValue = symbolStartAddressDecimalValue + symbolSizeDecimalValue;
			                                  }

			                                  if ([_symbolNameToAddressMap objectForKey:symbolName] != nil) {
				                                  if (symbolSizeDecimalValue > 0) {
					                                  [_duplicatedSymbols addObject:symbolAddress];
				                                  }
				                                  return;
			                                  }

			                                  [_symbolNameToAddressMap setValue:symbolAddress forKey:symbolName];
		                                  }
	                                  }];
}

@end

NS_ASSUME_NONNULL_END

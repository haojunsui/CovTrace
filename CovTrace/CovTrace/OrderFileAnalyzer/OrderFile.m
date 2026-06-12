#import "OrderFile.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OrderFile

- (instancetype)initWithContent:(NSString *)content linkmap:(Linkmap *)linkmap {
	self = [super init];
	if (self) {
		_content = content;
		_linkmap = linkmap;
		_symbolNameToAddressMap = [NSMutableDictionary dictionary];
		_nonApplicableSymbols = [NSMutableArray array];

		[self processSymbolsWithLinkmap:linkmap];
	}
	return self;
}

- (void)processSymbolsWithLinkmap:(Linkmap *)linkmap {
	NSRegularExpression *regexOrderFileSymbol = [NSRegularExpression
	    regularExpressionWithPattern:@"(.+)"
	                         options:0
	                           error:nil];
	[regexOrderFileSymbol enumerateMatchesInString:_content
	                                       options:0
	                                         range:NSMakeRange(0, [_content length])
	                                    usingBlock:^(NSTextCheckingResult *_Nullable result, __unused NSMatchingFlags flags, BOOL *_Nonnull stop) {
		                                    if (result == nil)
			                                    *stop = YES;

		                                    NSString *symbol = [_content substringWithRange:[result rangeAtIndex:1]];

		                                    SymbolAddress *symbolAddressInLinkmap = [[linkmap symbolNameToAddressMap] objectForKey:symbol];
		                                    if (symbolAddressInLinkmap == nil) {
			                                    [_nonApplicableSymbols addObject:symbol];
			                                    return;
		                                    }

		                                    [_symbolNameToAddressMap setObject:symbolAddressInLinkmap forKey:symbol];
	                                    }];
}

- (NSSet<NSNumber *> *)pageIndexSetWithPageSize:(unsigned long long)pageSize {
	NSMutableSet<NSNumber *> *pageIndexSet = [NSMutableSet set];

	SymbolAddress *sectionTextAddress = [_linkmap symbolAddressForSegment:@"TEXT" section:@"text"];

	for (SymbolAddress *address in [_symbolNameToAddressMap allValues]) {
		[pageIndexSet addObject:@(([address start] - [sectionTextAddress start]) / pageSize)];
	}

	return pageIndexSet;
}

@end

NS_ASSUME_NONNULL_END

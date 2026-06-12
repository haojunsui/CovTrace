#import "SymbolAddress.h"

NS_ASSUME_NONNULL_BEGIN

@implementation SymbolAddress

- (instancetype)initWithStartAddress:(unsigned long long)start size:(unsigned long long)size {
	self = [super init];
	if (self) {
		_start = start;
		_size = size;
	}
	return self;
}

@end

NS_ASSUME_NONNULL_END

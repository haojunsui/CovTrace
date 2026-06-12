#import <Foundation/Foundation.h>

@interface SymbolAddress : NSObject

@property (nonatomic) unsigned long long start;
@property (nonatomic) unsigned long long size;

- (instancetype)initWithStartAddress:(unsigned long long)start size:(unsigned long long)size;

@end

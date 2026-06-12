#import <Foundation/Foundation.h>

#import "Linkmap.h"

@interface OrderFile : NSObject

@property (nonatomic, readonly) NSString *content;
@property (nonatomic, readonly) Linkmap *linkmap;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SymbolAddress *> *symbolNameToAddressMap;
@property (nonatomic, readonly) NSMutableArray<NSString *> *nonApplicableSymbols;

- (instancetype)initWithContent:(NSString *)content linkmap:(Linkmap *)linkmap;

- (NSSet<NSNumber *> *)pageIndexSetWithPageSize:(unsigned long long)pageSize;

@end

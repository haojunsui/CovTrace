#import <Foundation/Foundation.h>

#import "SymbolAddress.h"

typedef NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, SymbolAddress *> *> LinkmapSections;

@interface Linkmap : NSObject

@property (nonatomic, readonly) NSString *content;

@property (nonatomic, readonly) LinkmapSections *sections;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SymbolAddress *> *symbolNameToAddressMap;
@property (nonatomic, readonly) NSMutableArray<SymbolAddress *> *duplicatedSymbols;
@property (nonatomic, readonly) NSMutableArray<SymbolAddress *> *addressJumpedSymbols;

@property (nonatomic) unsigned long long size;

- (instancetype)initWithContent:(NSString *)content;

- (SymbolAddress *)symbolAddressForSegment:(NSString *)segment section:(NSString *)section;

@end

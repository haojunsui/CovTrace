#import "symbolicator.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Private Core Symbolicator Framework

// This section is extracted from https://github.com/mountainstorm/CoreSymbolication
// Apple does not publish documentation of this framework publicly, but it's included in Xcode atos symbolication tool
// If Apple decided to update signature of this framework and we don't have updated function signatures
// we should use atos instead from a separate script to symbolicate

struct sCSTypeRef {
	void *csCppData; // typically retrieved using CSCppSymbol...::data(csData & 0xFFFFFFF8)
	void *csCppObj;  // a pointer to the actual CSCppObject
};
typedef struct sCSTypeRef CSTypeRef;

typedef CSTypeRef CSSymbolicatorRef;
typedef CSTypeRef CSSymbolRef;

extern CSSymbolicatorRef CSSymbolicatorCreateWithURLAndArchitecture(CFURLRef url, cpu_type_t type);
extern CSSymbolRef CSSymbolicatorGetSymbolWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
extern const char *CSSymbolGetMangledName(CSSymbolRef sym);

#pragma mark -

@interface ModuleAddress : NSObject
@property (nonatomic) NSString *start;
@property (nonatomic) NSString *end;
@property (nonatomic) NSString *vm_slide;
@end

@implementation ModuleAddress
@end

NSDictionary<NSURL *, NSArray<NSString *> *> *GetMangledFunctionsFromURL(NSURL *inputURL, NSString *_Nullable appPath) {
	NSString *content = [NSString stringWithContentsOfURL:inputURL encoding:NSUTF8StringEncoding error:nil];

	NSMutableArray *funcAddresses = [NSMutableArray array];
	NSMutableDictionary<NSURL *, ModuleAddress *> *moduleInfo = [NSMutableDictionary dictionary];

	// Function address example
	// 0x1023ab8c4
	NSRegularExpression *addressRegex = [NSRegularExpression regularExpressionWithPattern:@"(0x[\\d|\\w]+)\\n" options:NSRegularExpressionCaseInsensitive error:nil];

	[addressRegex enumerateMatchesInString:content
	                               options:0
	                                 range:NSMakeRange(0, [content length])
	                            usingBlock:^(NSTextCheckingResult *match, __unused NSMatchingFlags flags, __unused BOOL *stop) {
		                            [funcAddresses addObject:[content substringWithRange:[match rangeAtIndex:1]]];
	                            }];

	// Module info example
	// 0x1022e8000 - 0x10cc8ffff: /Users/hasui/Library/Developer/CoreSimulator/Devices/CFE38225-E8DB-4044-A96C-EAB837E6F42C/data/Containers/Bundle/Application/32B05541-3654-4125-931B-D5884A17FACA/Word.app/Word (36601856)
	NSRegularExpression *moduleRegex = [NSRegularExpression regularExpressionWithPattern:@"([\\w|\\d]+)\\s-\\s([\\w|\\d]+)\\:\\s(.+)\\s\\((\\d+)\\)" options:NSRegularExpressionCaseInsensitive error:nil];

	[moduleRegex enumerateMatchesInString:content
	                              options:0
	                                range:NSMakeRange(0, [content length])
	                           usingBlock:^(NSTextCheckingResult *match, __unused NSMatchingFlags flags, __unused BOOL *stop) {
		                           NSURL *moduleURL = [NSURL fileURLWithPath:[content substringWithRange:[match rangeAtIndex:3]]];

		                           // Example loaded Word iOS image path on device is /private/var/containers/Bundle/Application/E3DE59AB-D9E0-4D01-8CAC-6D77DFEEDD59/Word.app/Word
		                           // So we need to replace the prefix to provided app path
		                           if (appPath != nil && [[moduleURL path] hasPrefix:@"/private/var/containers/Bundle/Application"]) {
			                           NSArray *moduleURLComponents = [moduleURL pathComponents];
			                           NSArray *binaryPathComponentsRelativeToBundle = [moduleURLComponents subarrayWithRange:NSMakeRange(8, [moduleURLComponents count] - 8)];
			                           NSString *binaryPathRelativeToBundle = [NSString pathWithComponents:binaryPathComponentsRelativeToBundle];

			                           moduleURL = [NSURL fileURLWithPath:binaryPathRelativeToBundle relativeToURL:[NSURL fileURLWithPath:appPath]];
		                           }

		                           ModuleAddress *addr = [[ModuleAddress alloc] init];
		                           [addr setStart:[content substringWithRange:[match rangeAtIndex:1]]];
		                           [addr setEnd:[content substringWithRange:[match rangeAtIndex:2]]];
		                           [addr setVm_slide:[content substringWithRange:[match rangeAtIndex:4]]];

		                           [moduleInfo setObject:addr forKey:moduleURL];
	                           }];

	// Usually functions from same module are close to each other in execution order.
	// For performance, let's check whether it's from last module that we checked.
	NSURL *lastLookedModuleURL = nil;
	ModuleAddress *lastLookedModuleAddress = nil;

	NSMutableDictionary<NSURL *, NSMutableArray *> *moduleToFuncAddresses = [NSMutableDictionary dictionary];

	for (NSString *addr in funcAddresses) {
		if (lastLookedModuleURL != nil) {
			if ([addr compare:[lastLookedModuleAddress start]] != NSOrderedAscending && [addr compare:[lastLookedModuleAddress end]] != NSOrderedDescending) {
				if ([moduleToFuncAddresses objectForKey:lastLookedModuleURL] == nil) {
					NSMutableArray *array = [NSMutableArray array];
					[moduleToFuncAddresses setObject:array forKey:lastLookedModuleURL];
				}
				[[moduleToFuncAddresses objectForKey:lastLookedModuleURL] addObject:addr];
				continue;
			}
		}

		for (NSURL *moduleURL in moduleInfo) {
			if ([addr compare:[[moduleInfo objectForKey:moduleURL] start]] != NSOrderedAscending && [addr compare:[[moduleInfo objectForKey:moduleURL] end]] != NSOrderedDescending) {
				if ([moduleToFuncAddresses objectForKey:moduleURL] == nil) {
					NSMutableArray *array = [NSMutableArray array];
					[moduleToFuncAddresses setObject:array forKey:moduleURL];
				}
				[[moduleToFuncAddresses objectForKey:moduleURL] addObject:addr];
				lastLookedModuleURL = moduleURL;
				lastLookedModuleAddress = [moduleInfo objectForKey:moduleURL];
				break;
			}
		}
	}

	NSMutableDictionary *moduleToFunc = [NSMutableDictionary dictionary];

	for (NSUInteger moduleIndex = 0; moduleIndex < [moduleToFuncAddresses count]; moduleIndex++) {
		NSURL *moduleUrl = [[moduleToFuncAddresses allKeys] objectAtIndex:moduleIndex];
		NSLog(@"[%2lu/%2lu] - Symbolicating %@", moduleIndex + 1, [moduleToFuncAddresses count], [moduleUrl lastPathComponent]);

		// For iOS, module url is local to device /private/var/containers/Bundle/Application/<UUID>/<AppName>.app/<AppName>
		if (![moduleUrl checkResourceIsReachableAndReturnError:nil]) {
			continue;
		}

		unsigned long long moduleSlide;

		// See CMachFileImage.cpp
		// The rules for computing a symbol offset into a module are somewhat tricky. Emperical observation
		// indicates that for the application image, we need to subtract the vmaddr_slide but for non-app
		// images such as frameworks or dylibs, we need to subtract the code start of the image. Ugh.
		if ([[moduleUrl absoluteString] containsString:@"Contents/MacOS"] || ![[moduleUrl absoluteString] containsString:@".app/Contents"]) {
			moduleSlide = [[moduleInfo objectForKey:moduleUrl].vm_slide longLongValue];
		} else {
			NSScanner *scanner = [NSScanner scannerWithString:[[moduleInfo objectForKey:moduleUrl] start]];
			[scanner scanHexLongLong:&moduleSlide];
		}

		NSMutableArray *funcArray = [NSMutableArray array];

		int successCount = 0;
		int unresolvedCount = 0;

		for (NSString *addr in [moduleToFuncAddresses objectForKey:moduleUrl]) {
			CSSymbolicatorRef cs = CSSymbolicatorCreateWithURLAndArchitecture((__bridge CFURLRef)moduleUrl, 16777228 /* arm64 cputype */);

			unsigned long long funcAddr;
			NSScanner *scanner = [NSScanner scannerWithString:addr];
			[scanner scanHexLongLong:&funcAddr];

			CSSymbolRef symbol = CSSymbolicatorGetSymbolWithAddressAtTime(cs, funcAddr - moduleSlide, 0);
			const char *mangledName = CSSymbolGetMangledName(symbol);

			if (mangledName != NULL) {
				NSString *funcName = [NSString stringWithFormat:@"%s", mangledName];
				if (![funcArray containsObject:funcName]) {
					[funcArray addObject:funcName];
					successCount += 1;
				}
			} else {
				unresolvedCount += 1;
			}
		}

		if ([funcArray count] > 0) {
			[moduleToFunc setObject:funcArray forKey:moduleUrl];
		}

		if (unresolvedCount > 0) {
			// Some function address was not symbolicated, we want to know which framework and the stats
			NSLog(@"\t\e[1;32mMangled Symbols: %d\e[m\n", successCount);
			NSLog(@"\t\e[1;31mUnresolved Symbols: %d\e[m\n", unresolvedCount);
			NSLog(@"\tSuccess Rate: %.1f%%", successCount * 100.0 / (successCount + unresolvedCount));
		}
	}

	return moduleToFunc;
}

void WriteMangledFunctions(NSString *inputPath, NSString *outputPath, NSString *_Nullable appPath) {
	NSURL *outputURL = [NSURL fileURLWithPath:outputPath isDirectory:YES];
	if (![outputURL checkResourceIsReachableAndReturnError:nil]) {
		[[NSFileManager defaultManager] createDirectoryAtURL:outputURL
		                         withIntermediateDirectories:YES
		                                          attributes:nil
		                                               error:nil];
	}

	NSDictionary *functionDict = GetMangledFunctionsFromURL([NSURL fileURLWithPath:inputPath isDirectory:NO], appPath);
	for (NSURL *moduleUrl in functionDict) {
		// make a file name to write the data to using the documents directory:
		NSString *fileName = [NSString stringWithFormat:@"%@.order", [moduleUrl lastPathComponent]];
		NSURL *outputFileURL = [outputURL URLByAppendingPathComponent:fileName isDirectory:NO];

		NSString *funcs = [[functionDict objectForKey:moduleUrl] componentsJoinedByString:@"\n"];
		NSString *contentToWrite = [NSString stringWithFormat:@"%@", funcs];
		[contentToWrite writeToURL:outputFileURL
		                atomically:NO
		                  encoding:NSStringEncodingConversionAllowLossy
		                     error:nil];
	}
}

NS_ASSUME_NONNULL_END

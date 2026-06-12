#import "Linkmap.h"
#import "OrderFile.h"
#import "OrderFileAnalyzer.h"
#import "SymbolAddress.h"
#import "NSString+Hex.h"

NS_ASSUME_NONNULL_BEGIN

/*
 Order File Performance Analyzer
 1. Read linkmap file and gather start address and byte size of __text section. Determine total number of virtual pages needed to be assigned.
 2. Read all symbols from __text section, and gather their address, size, and name.
 3. Detect any duplicated symbols or symbols that has address jumped.
 4. Read all symbols from order file, map them to linkmap, and gather their address and size.
 5. # of virtual pages that will be assigned before ordering = set count of symbol address / virtual page size.
 6. # of virtual pages that will be assigned after ordering = total size of order file symbols / virtual page size.
 7. # of vitual pages faults that will be saved = # of virtual pages before ordering - # of virtual pages after ordering
 8. Estimated time saved = # of vitual pages faults saved * estimated page fault time
 */

// iOS / macOS ARM virtual memory page size is 16k
// macOS Intel virtual memory page size is 4k
// https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/AboutMemory.html
#define VM_PAGE_SIZE_LINK_IOS_MAC_ARM (16 * 1024)
#define VM_PAGE_SIZE_LINK_MAC_INTEL (4 * 1024)

// Total time of paging for conventional computers using hard disk drives is near 8ms
// Since SSD is faster than HDD, let's assume the time of paging for SSD is 0.5ms
// https://en.wikipedia.org/wiki/Page_fault
#define ESTIMATED_PAGE_FAULT_TIME_MS 0.5

unsigned long long GetVMPageSizeFromPath(NSString *linkmapPath) {
	if ([linkmapPath containsString:@"/ios/"] || [linkmapPath containsString:@"/mac_arm64/"]) {
		return VM_PAGE_SIZE_LINK_IOS_MAC_ARM;
	} else if ([linkmapPath containsString:@"/mac_intel/"]) {
		return VM_PAGE_SIZE_LINK_MAC_INTEL;
	}

	return 0;
}

unsigned long long GetTotalSymbolSize(NSArray<SymbolAddress *> *symbols) {
	unsigned long long totalSize = 0;
	for (SymbolAddress *symbol in symbols) {
		totalSize += [symbol size];
	}
	return totalSize;
}

void AnalyzeOrderFileWithLinkmap(NSString *orderFilePath, NSString *linkmapPath) {
	NSURL *orderFileURL = [NSURL fileURLWithPath:orderFilePath isDirectory:NO];
	NSURL *linkmapURL = [NSURL fileURLWithPath:linkmapPath isDirectory:NO];

	if (![orderFileURL checkResourceIsReachableAndReturnError:nil] || ![linkmapURL checkResourceIsReachableAndReturnError:nil]) {
		NSLog(@"Error: order file or linkmap is not reachable...");
		return;
	}

	NSString *linkmapContent = [NSString stringWithContentsOfFile:linkmapPath encoding:NSASCIIStringEncoding error:nil];
	if (linkmapContent == nil) {
		NSLog(@"Error: cannot parse linkmap content...");
		return;
	};

	NSString *orderpFileContent = [NSString stringWithContentsOfFile:orderFilePath encoding:NSASCIIStringEncoding error:nil];
	if (orderpFileContent == nil) {
		NSLog(@"Error: cannot parse order file content...");
		return;
	};

	Linkmap *linkmap = [[Linkmap alloc] initWithContent:linkmapContent];
	OrderFile *orderFile = [[OrderFile alloc] initWithContent:orderpFileContent linkmap:linkmap];

	unsigned long long vmPageSize = GetVMPageSizeFromPath(linkmapPath);
	NSUInteger orderFileSymbolsVMPageIndexCount = [[orderFile pageIndexSetWithPageSize:vmPageSize] count];
	unsigned long long orderFileSymbolsVMPageCount = (long long)ceil(GetTotalSymbolSize([[orderFile symbolNameToAddressMap] allValues]) * 1.0 / vmPageSize);

	SymbolAddress *sectionTextAddress = [linkmap symbolAddressForSegment:@"TEXT" section:@"text"];

	NSLog(@"Linkmaps __TEXT summary:\n");
	NSLog(@"\tBegin address: %s\n", [[NSString hexFromDecimal:[sectionTextAddress start]] UTF8String]);
	NSLog(@"\tAssigned size: %@\n", [NSByteCountFormatter stringFromByteCount:(long long)[sectionTextAddress size] countStyle:NSByteCountFormatterCountStyleFile]);
	NSLog(@"\tTotal symbols count: %lu\n", [[linkmap symbolNameToAddressMap] count]);
	NSLog(@"\tDuplicate symbols size: %@\n", [NSByteCountFormatter stringFromByteCount:GetTotalSymbolSize([linkmap duplicatedSymbols]) countStyle:NSByteCountFormatterCountStyleFile]);
	NSLog(@"\t# of address jumped symbols: %lu\n", [[linkmap addressJumpedSymbols] count]);
	NSLog(@"\t# of VM pages assigned: %lld\n", (long long)ceil([sectionTextAddress size] * 1.0 / vmPageSize));
	NSLog(@"Order file summary:\n");
	NSLog(@"\t# of ordered symbols: %lu\n", [[orderFile symbolNameToAddressMap] count]);
	NSLog(@"\t# of non-applicable symbols: %lu\n", [[orderFile nonApplicableSymbols] count]);
	NSLog(@"\t# of VM pages faults on startup before ordering: %lu\n", orderFileSymbolsVMPageIndexCount);
	NSLog(@"\t# of VM pages faults on startup after ordering: %llu\n", orderFileSymbolsVMPageCount);
	NSLog(@"\t# of page faults saved: %llu\n", orderFileSymbolsVMPageIndexCount - orderFileSymbolsVMPageCount);
	NSLog(@"\tEstimated time saved: %.0f ms\n", (orderFileSymbolsVMPageIndexCount - orderFileSymbolsVMPageCount) * ESTIMATED_PAGE_FAULT_TIME_MS);
}

NS_ASSUME_NONNULL_END

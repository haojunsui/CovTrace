#import <Foundation/Foundation.h>
#import "OrderFileAnalyzer.h"

int main(__unused int argc, const char *argv[]) {
	@autoreleasepool {
		if (argc < 3) {
			NSLog(@"\n usage: orderfileanalyzer <orderFilePath> <linkmapPath> \n\n");
			return -1;
		}

		NSString *orderFilePath = [NSString stringWithFormat:@"%s", argv[1]];
		NSString *linkmapPath = [NSString stringWithFormat:@"%s", argv[2]];

		AnalyzeOrderFileWithLinkmap(orderFilePath, linkmapPath);
	}
	return 0;
}

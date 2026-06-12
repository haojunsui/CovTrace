#import "symbolicator.h"
#import <Foundation/Foundation.h>

int main(__unused int argc, __unused const char *argv[]) {
	@autoreleasepool {
		NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];

		if ([arguments count] < 3) {
			NSLog(@"\n usage: csansymbolicator -i <input> -o <output> [-a appPath] \n\n");
			return -1;
		}

		NSString *inputPath = nil;
		NSString *outputPath = nil;
		NSString *appPath = nil;

		for (NSUInteger i = 1; i < ([arguments count] - 1); i++) {
			NSString *currentArg = [arguments objectAtIndex:i];
			NSString *nextArg = [arguments objectAtIndex:(i + 1)];

			if ([currentArg isEqualToString:@"-i"]) {
				inputPath = nextArg;
				i++;
			} else if ([currentArg isEqualToString:@"-o"]) {
				outputPath = nextArg;
				i++;
			} else if ([currentArg isEqualToString:@"-a"]) {
				appPath = nextArg;
				i++;
			}
		}

		WriteMangledFunctions(inputPath, outputPath, appPath);
	}
	return 0;
}

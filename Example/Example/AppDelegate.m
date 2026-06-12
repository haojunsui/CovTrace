//
//  AppDelegate.m
//  Example
//
//  Created by Haojun Sui on 6/11/26.
//

#import "AppDelegate.h"

extern void CsanDumpLoadedModuleInfo(void);

@interface AppDelegate ()

@end

@implementation AppDelegate

+ (void)load {
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// Insert code here to initialize your application
	CsanDumpLoadedModuleInfo();
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return YES;
}


@end

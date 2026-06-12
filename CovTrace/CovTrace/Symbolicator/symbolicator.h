#import <Foundation/Foundation.h>

/// @brief Write dictionary of module name to mangled function array to provided url, filename will be the module name.orderfile, content is separate by newline
/// @param inputPath input file path that contains the function address and module offsets + slide
/// @param outputPath output directory path to output file that contains the mangled function name
/// @param appPath [optional] application bundle path override for iOS since loaded app path is in /private/var/containers/Bundle/Application
void WriteMangledFunctions(NSString *inputPath, NSString *outputPath, NSString *appPath);

// This file must remain as plain C/C++ to prevent Objective-C method swizzling to
// cause sanitizer APIs <-> swizzled method infinite loop

#include "coveragesanitizer.h"
#include <assert.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *CsanFileName = "/Library/csan.txt";

static bool sStopCollecting = false;
static bool sTraceInited = false;

__attribute__((no_sanitize("coverage"))) bool ShouldOutputSymbolAddress(void)
{
//	static bool shouldOutputSymbolAddress = false;
//	static bool didReadFromEnv = false;
//	if (!didReadFromEnv)
//	{
//		shouldOutputSymbolAddress = getenv("CSAN_OUTPUT_SYMBOL_ADDRESS") != NULL;
//		didReadFromEnv = true;
//	}
//	return shouldOutputSymbolAddress;
	return true;
}

__attribute__((no_sanitize("coverage"))) char *GetCsanFilePath(void)
{
	static char *fullPath = NULL;

	if (fullPath == NULL)
	{
		const char *home = getenv("HOME");
		const char *cfilePath = CsanFileName;

		if (home == NULL)
		{
			perror("HOME not found.\n");
			assert(false);
		}

		size_t totalLen = strlen(home) + strlen(cfilePath) + 1;
		fullPath = (char *)malloc(totalLen);
		if (fullPath == NULL)
		{
			perror("Memory allocation failed.\n");
			assert(false);
		}

		strcpy(fullPath, home);
		strcat(fullPath, cfilePath);
	}

	return fullPath;
}

__attribute__((no_sanitize("coverage"))) FILE *GetCsanFileHandle(void)
{
	static FILE *fileHandle = NULL;

	if (fileHandle == NULL)
	{
		char *fullPath = GetCsanFilePath();

		if (fullPath != NULL)
		{
			fileHandle = fopen(fullPath, "a");
		}

		if (!fileHandle)
		{
			fprintf(stderr, "Failed to open file at %s.\n", fullPath);
			assert(false);
		}

		// Ensure output is unbuffered. Otherwise output may not be observed in time.
		setvbuf(fileHandle, NULL, _IONBF, 0);
	}

	return fileHandle;
}

// This callback is inserted by the compiler as a module constructor
// into every DSO. 'start' and 'stop' correspond to the
// beginning and end of the section with the guards for the entire
// binary (executable or DSO). The callback will be called at least
// once per DSO and may be called multiple times with the same parameters.
__attribute__((no_sanitize("coverage"))) void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop)
{
	if (!ShouldOutputSymbolAddress())
	{
		remove(GetCsanFilePath());
	}

	// Counter for the guards.
	static uint32_t N;

	// Initialize only once.
	if (start == NULL || *start || start == stop)
	{
		return;
	}

	for (uint32_t *x = start; x < stop; x++)
	{
		// Guards should start from 1.
		*x = ++N;
	}
	
	sTraceInited = true;
}

// This callback is inserted by the compiler on every edge in the
// control flow (some optimizations apply).
// Typically, the compiler will emit the code like this:
//    if(*guard)
//      __sanitizer_cov_trace_pc_guard(guard);
// But for large functions it will emit a simple call:
//    __sanitizer_cov_trace_pc_guard(guard);
__attribute__((no_sanitize("coverage"))) void __sanitizer_cov_trace_pc_guard(uint32_t *guard)
{
	// +[load] functions will run before __sanitizer_cov_trace_pc_guard_init is called, so need to populate necessary global static in such case.
	if (ShouldOutputSymbolAddress())
	{
		// If initialization has not occurred yet (meaning that guard is uninitialized), that means that initial functions like +load are being run. These functions will only be run once anyways, so we should always allow them to be recorded and ignore guard
		if (sTraceInited && (sStopCollecting || (guard != NULL && !(*guard))))
		{
			return;
		}

		// If you set *guard to 0 this code will not be called again for this edge.
		if (guard != NULL)
		{
			*guard = 0;
		}

		fprintf(GetCsanFileHandle(), "%p\n", __builtin_return_address(0));
	}
}

// Return true if loaded module is system module
__attribute__((no_sanitize("coverage"))) bool FIsSystemPath(const char *szPath)
{
	if (strncmp(szPath, "/usr/", 5) == 0)
		return true;

	if (strncmp(szPath, "/System/", 8) == 0)
		return true;

	if (strncmp(szPath, "/Library/", 9) == 0)
		return true;

	return false;
}

__attribute__((no_sanitize("coverage"))) void CsanDumpLoadedModuleInfo(void)
{
#if !MS_TARGET_IOS
	sStopCollecting = true;
	__sync_synchronize();
#endif

	if (ShouldOutputSymbolAddress())
	{
		// Iterate through all the loaded images
		uint32_t imageCount = _dyld_image_count();
		for (uint32_t imageIndex = 0; imageIndex < imageCount; ++imageIndex)
		{
			const char *szPath = _dyld_get_image_name(imageIndex);

			if (szPath == NULL || FIsSystemPath(szPath))
			{
				continue;
			}

			const struct mach_header *header = _dyld_get_image_header(imageIndex);

			// Traverse through the load commands to find __TEXT segment
			struct load_command *cmd = (struct load_command *)((char *)header + sizeof(struct mach_header_64));
			for (uint32_t j = 0; j < header->ncmds; j++)
			{
				if (cmd->cmd == LC_SEGMENT_64)
				{
					struct segment_command_64 *seg_cmd = (struct segment_command_64 *)cmd;
					if (strcmp(seg_cmd->segname, "__TEXT") == 0)
					{
						intptr_t vmaddr_slide = _dyld_get_image_vmaddr_slide(imageIndex);
						void *startAddress = (void *)(seg_cmd->vmaddr + vmaddr_slide);
						void *endAddress = (void *)(seg_cmd->vmaddr + seg_cmd->vmsize + vmaddr_slide - 1); // endAddress is the last valid address of the module, it should be len-1 since OS VM address start from 0, like, start 0, len 10, the valid address should be 0-9.

						fprintf(GetCsanFileHandle(), "%p - %p: %s (%ld)\n", startAddress, endAddress, szPath, vmaddr_slide);
						break;
					}
				}

				cmd = (struct load_command *)((char *)cmd + cmd->cmdsize);
			}
		}
#if !MS_TARGET_IOS
		fclose(GetCsanFileHandle());
#endif
	}
}

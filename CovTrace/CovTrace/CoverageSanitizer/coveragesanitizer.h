#include <stdint.h>

extern const char *CsanFileName;

/// @brief Write to stdout with all loaded module info with module start/end addresses, url, and its vmslide address in current session
/// @brief Example: 0x1022e8000 - 0x10cc8ffff: /Users/hasui/Library/Developer/CoreSimulator/Devices/CFE38225-E8DB-4044-A96C-EAB837E6F42C/data/Containers/Bundle/Application/32B05541-3654-4125-931B-D5884A17FACA/Word.app/Word (36601856)
#ifdef __cplusplus
extern "C" {
#endif
void CsanDumpLoadedModuleInfo(void);
#ifdef __cplusplus
}
#endif

#pragma mark - Coverage Sanitizer Symbol

/// @brief Initialize all function guards that is between beginning and end of the section with the guards for the entire binary (executable or DSO). The guards are [start, stop). This function will be called at least once per DSO and may be called more than once with the same values of start/stop.
/// @param start begin guard for the entire binary (executable or DSO)
/// @param stop end guard for the entire binary (executable or DSO)
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop);

/// @brief Write to stdout with current functun's builtin return address
/// @param guard guard check to prevent code being called multiple times for the same edge
void __sanitizer_cov_trace_pc_guard(uint32_t *guard);

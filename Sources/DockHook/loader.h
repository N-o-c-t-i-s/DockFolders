#ifndef DF_LOADER_H
#define DF_LOADER_H

#include <sys/types.h>
#include <stddef.h>

/// Loads the dylib at `payload_path` into process `pid` (the Dock). Needs root, and SIP's
/// debugging restrictions off; on Apple silicon the caller must also be running as arm64e
/// (the -arm64e_preview_abi boot-arg). Returns 0 on success; on failure, fills `error`.
int df_inject(pid_t pid, const char *payload_path, char *error, size_t error_size);

#endif

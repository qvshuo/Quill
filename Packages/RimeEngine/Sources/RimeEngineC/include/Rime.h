#ifndef QUILL_RIME_H
#define QUILL_RIME_H

// stdbool-flavored librime C API for direct Swift interop (Squirrel style).
// Include order matters: the stdbool header redefines RIME_FLAVORED/Bool so that
// rime_api.h is parsed into the `_stdbool` types (RimeApi_stdbool, ...).
#include <rime_api_stdbool.h>
#include <rime_api.h>

#endif  // QUILL_RIME_H

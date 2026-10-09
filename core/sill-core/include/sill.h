/* sill-core C ABI — the seam every chrome backend shares.
 * Build `cargo build -p sill-core` → lib/lib sill_core.a, then link this.
 * All returned char* are heap JSON strings: free with sill_str_free().
 */
#ifndef SILL_H
#define SILL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SillScanner SillScanner;

SillScanner *sill_scanner_new(void);
void         sill_scanner_free(SillScanner *scanner);

/* Feed raw PTY bytes; returns a JSON array of events:
 *   [{"type":"status","state":"blocked","kind":"permission","app":"..."}, ...]
 * Event types: status, command_mark, cwd, link, notify, progress,
 * clipboard_write. Unknown OSC never produces an event and never harms the
 * stream. Returns NULL on error. */
char *sill_scanner_feed_json(SillScanner *scanner, const uint8_t *data, size_t len);

/* Parse layout.toml text → {"ok":true,"layout":{...}} or {"ok":false,"error":...}. */
char *sill_layout_parse_json(const char *toml_text);

/* Ghostty config text → JSON ImportReport {entries,mapped,similar,dropped,config_toml}. */
char *sill_import_ghostty_json(const char *ghostty_config);

/* Free a string returned by any sill_* function. */
void sill_str_free(char *s);

/* Static version string — do not free. */
const char *sill_version(void);

#ifdef __cplusplus
}
#endif
#endif /* SILL_H */

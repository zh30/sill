//! C ABI for chrome backends (include/sill.h).
//!
//! The macOS/Linux chrome calls into here for stream scanning and layout
//! parsing so every backend speaks the same protocol logic. Strings returned
//! are JSON, heap-allocated; free them with `sill_str_free`.

use crate::layout::Layout;
use crate::osc::OscScanner;
use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

/// Opaque handle.
pub struct SillScanner {
    inner: OscScanner,
}

#[no_mangle]
pub extern "C" fn sill_scanner_new() -> *mut SillScanner {
    Box::into_raw(Box::new(SillScanner {
        inner: OscScanner::new(),
    }))
}

/// # Safety
/// `scanner` must be a pointer from `sill_scanner_new` (or null).
#[no_mangle]
pub unsafe extern "C" fn sill_scanner_free(scanner: *mut SillScanner) {
    if !scanner.is_null() {
        drop(Box::from_raw(scanner));
    }
}

fn into_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

/// Feed PTY bytes; returns a JSON array of OscEvent (see src/osc.rs).
/// Returns null on panic or NUL-containing payload.
///
/// # Safety
/// `data` must point to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn sill_scanner_feed_json(
    scanner: *mut SillScanner,
    data: *const u8,
    len: usize,
) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if scanner.is_null() || (data.is_null() && len > 0) {
            return ptr::null_mut();
        }
        let bytes = if len == 0 {
            &[][..]
        } else {
            std::slice::from_raw_parts(data, len)
        };
        let events = (*scanner).inner.feed(bytes);
        match serde_json::to_string(&events) {
            Ok(j) => into_c_string(j),
            Err(_) => ptr::null_mut(),
        }
    }));
    res.unwrap_or(ptr::null_mut())
}

/// Parse layout TOML text → normalized JSON {ok: bool, layout|error}.
///
/// # Safety
/// `toml_text` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn sill_layout_parse_json(toml_text: *const c_char) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if toml_text.is_null() {
            return ptr::null_mut();
        }
        let cstr = std::ffi::CStr::from_ptr(toml_text);
        let text = match cstr.to_str() {
            Ok(t) => t,
            Err(_) => return into_c_string(r#"{"ok":false,"error":"invalid utf-8"}"#.into()),
        };
        match toml::from_str::<Layout>(text) {
            Ok(l) => into_c_string(serde_json::json!({"ok": true, "layout": l}).to_string()),
            Err(e) => {
                into_c_string(serde_json::json!({"ok": false, "error": e.to_string()}).to_string())
            }
        }
    }));
    res.unwrap_or(ptr::null_mut())
}

/// Import a Ghostty config → JSON ImportReport.
///
/// # Safety
/// `ghostty_config` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn sill_import_ghostty_json(ghostty_config: *const c_char) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if ghostty_config.is_null() {
            return ptr::null_mut();
        }
        let cstr = std::ffi::CStr::from_ptr(ghostty_config);
        let text = match cstr.to_str() {
            Ok(t) => t,
            Err(_) => return ptr::null_mut(),
        };
        let report = crate::ghostty_import::import_ghostty_config(text);
        match serde_json::to_string(&report) {
            Ok(j) => into_c_string(j),
            Err(_) => ptr::null_mut(),
        }
    }));
    res.unwrap_or(ptr::null_mut())
}

/// Free a string returned by any sill_* function.
///
/// # Safety
/// `s` must be a pointer previously returned by this library (or null).
#[no_mangle]
pub unsafe extern "C" fn sill_str_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Core version string (static — do not free).
#[no_mangle]
pub extern "C" fn sill_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

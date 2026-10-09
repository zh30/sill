//! sill-core — pure-logic core for the Sill agent terminal.
//!
//! The terminal core itself is libghostty (the only VT parser, vendored
//! separately). This crate owns everything *around* it that must be identical
//! across chrome backends: the OSC 7501/133/7/8 event scanner (a tee on the
//! PTY byte stream, off the render thread), the five-point status model,
//! `layout.toml`, and the Ghostty import mapping.

pub mod ffi;
pub mod ghostty_import;
pub mod layout;
pub mod osc;
pub mod state;

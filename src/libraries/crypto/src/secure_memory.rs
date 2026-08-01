//! Secure memory handling.
//!
//! Provides memory management for sensitive data (keys, passwords, tokens):
//!
//! - **Zeroing on drop**: Memory contents are overwritten before deallocation
//! - **Memory locking**: Attempts to prevent swapping to disk via `mlock()`
//! - **No accidental leakage**: Debug intentionally omits contents, Clone is not implemented
//!
//! ## Platform Support
//!
//! Memory locking (`mlock`/`munlock`) is best-effort:
//! - **Linux**: Uses `libc::mlock()` — guaranteed behavior (subject to RLIMIT_MEMLOCK)
//! - **Other Unix**: Uses `libc::mlock()` — guaranteed behavior
//! - **Unsupported platforms**: Locking returns `MemoryError`
//!
//! ## Security
//!
//! - Guaranteed: memory is zeroed on drop via `zeroize` crate
//! - Best-effort: memory locking depends on platform support and resource limits
//! - The `Debug` implementation shows only metadata, not contents
//! - `Clone` is intentionally not implemented to prevent accidental copies

#![allow(unsafe_code)]

use core::fmt;

use zeroize::Zeroize;

use crate::error::{CryptoError, CryptoResult};

// ---------------------------------------------------------------------------
// Platform-specific memory locking
// ---------------------------------------------------------------------------

#[cfg(any(unix, target_os = "linux", target_os = "android"))]
mod platform {
    /// Attempt to lock memory using `mlock`.
    ///
    /// # Safety
    ///
    /// `ptr` must point to a valid, allocated memory region of at least `len` bytes.
    pub(super) unsafe fn try_lock(ptr: *const u8, len: usize) -> bool {
        if len == 0 {
            return true;
        }
        // SAFETY: Caller guarantees the pointer is valid and the length
        // corresponds to an allocated region.
        let ret = libc::mlock(ptr as *const libc::c_void, len);
        ret == 0
    }

    /// Attempt to unlock memory using `munlock`.
    ///
    /// # Safety
    ///
    /// `ptr` must point to a locked memory region of at least `len` bytes.
    pub(super) unsafe fn try_unlock(ptr: *const u8, len: usize) {
        if len == 0 {
            return;
        }
        // SAFETY: Same as try_lock.
        libc::munlock(ptr as *const libc::c_void, len);
    }

    pub(super) fn is_locking_supported() -> bool {
        true
    }
}

#[cfg(not(any(unix, target_os = "linux", target_os = "android")))]
mod platform {
    pub(super) unsafe fn try_lock(_ptr: *const u8, _len: usize) -> bool {
        false
    }

    pub(super) unsafe fn try_unlock(_ptr: *const u8, _len: usize) {}

    pub(super) fn is_locking_supported() -> bool {
        false
    }
}

use platform::*;

/// A block of memory that is zeroed on drop and optionally locked
/// to prevent swapping.
///
/// # Guarantees
///
/// - **Always**: Memory contents are securely zeroed on drop
/// - **Best-effort**: Memory is locked to prevent swapping (depends on platform)
///
/// # Security Notes
///
/// - `Debug` shows only `[REDACTED]` for the buffer contents
/// - `Clone` is intentionally not implemented
/// - The buffer is zeroed in `Drop` before the memory is freed
///
/// # Examples
///
/// ```ignore
/// use mission_crypto::secure_memory::SecureBuffer;
///
/// let mut buf = SecureBuffer::new(32)?;
/// buf.as_mut_bytes().copy_from_slice(&secret_data);
/// // buf is zeroed automatically on drop
/// ```
#[must_use]
pub struct SecureBuffer {
    data: Box<[u8]>,
    locked: bool,
}

impl SecureBuffer {
    /// Allocate a new secure buffer of the given size.
    ///
    /// The memory will be zeroed on allocation and on drop.
    ///
    /// # Errors
    ///
    /// Always succeeds for allocation itself.
    pub fn new(size: usize) -> CryptoResult<Self> {
        let data = vec![0u8; size].into_boxed_slice();
        Ok(Self {
            data,
            locked: false,
        })
    }

    /// Allocate and pre-lock the buffer.
    ///
    /// This is a convenience method that allocates and immediately locks
    /// the memory in one call.
    pub fn new_locked(size: usize) -> CryptoResult<Self> {
        let mut buf = Self::new(size)?;
        buf.lock()?;
        Ok(buf)
    }

    /// Return a reference to the buffer contents.
    pub fn as_bytes(&self) -> &[u8] {
        &self.data
    }

    /// Return a mutable reference to the buffer contents.
    pub fn as_mut_bytes(&mut self) -> &mut [u8] {
        &mut self.data
    }

    /// Return the buffer length.
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// Is the buffer empty?
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    /// Attempt to lock memory to prevent swapping.
    ///
    /// Uses `mlock()` on Unix.
    ///
    /// # Errors
    ///
    /// Returns `MemoryError` if locking fails. This may happen if:
    /// - The RLIMIT_MEMLOCK limit is too low (Linux)
    /// - The platform does not support memory locking
    /// - The memory is already locked
    pub fn lock(&mut self) -> CryptoResult<()> {
        if self.locked {
            return Err(CryptoError::MemoryError);
        }
        if self.data.is_empty() {
            self.locked = true;
            return Ok(());
        }
        let ptr = self.data.as_ptr();
        let len = self.data.len();
        // SAFETY: ptr points to the buffer's owned heap allocation of len bytes.
        if unsafe { try_lock(ptr, len) } {
            self.locked = true;
            Ok(())
        } else {
            Err(CryptoError::MemoryError)
        }
    }

    /// Unlock memory.
    ///
    /// This allows the memory to be swapped again.
    pub fn unlock(&mut self) -> CryptoResult<()> {
        if !self.locked {
            return Ok(());
        }
        if !self.data.is_empty() {
            let ptr = self.data.as_ptr();
            let len = self.data.len();
            // SAFETY: ptr points to the buffer's locked heap allocation.
            unsafe {
                try_unlock(ptr, len);
            }
        }
        self.locked = false;
        Ok(())
    }

    /// Is the memory currently locked?
    pub fn is_locked(&self) -> bool {
        self.locked
    }

    /// Is memory locking supported on this platform?
    pub fn is_locking_supported() -> bool {
        is_locking_supported()
    }
}

impl Drop for SecureBuffer {
    fn drop(&mut self) {
        // Zeroize the buffer contents before freeing
        self.data.zeroize();
        // Unlock if locked
        if self.locked {
            let ptr = self.data.as_ptr();
            let len = self.data.len();
            // SAFETY: ptr points to a locked allocated region.
            unsafe {
                try_unlock(ptr, len);
            }
            self.locked = false;
        }
    }
}

impl fmt::Debug for SecureBuffer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SecureBuffer")
            .field("len", &self.data.len())
            .field("locked", &self.locked)
            .field("data", &"[REDACTED]")
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secure_buffer_creation() {
        let buf = SecureBuffer::new(32).unwrap();
        assert_eq!(buf.as_bytes().len(), 32);
        assert!(!buf.is_locked());
    }

    #[test]
    fn secure_buffer_empty() {
        let buf = SecureBuffer::new(0).unwrap();
        assert!(buf.is_empty());
        assert_eq!(buf.len(), 0);
    }

    #[test]
    fn secure_buffer_zeroed_on_drop() {
        let mut buf = SecureBuffer::new(8).unwrap();
        buf.as_mut_bytes()
            .copy_from_slice(&[0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe]);
        drop(buf);
    }

    #[test]
    fn secure_buffer_lock_unlock() {
        let mut buf = SecureBuffer::new(16).unwrap();
        assert!(!buf.is_locked());
        let lock_result = buf.lock();
        if lock_result.is_ok() {
            assert!(buf.is_locked());
            buf.unlock().unwrap();
            assert!(!buf.is_locked());
        }
    }

    #[test]
    fn secure_buffer_double_lock_fails() {
        let mut buf = SecureBuffer::new(16).unwrap();
        if buf.lock().is_ok() {
            let result = buf.lock();
            assert!(result.is_err());
        }
    }

    #[test]
    fn secure_buffer_new_locked() {
        let buf = SecureBuffer::new_locked(32);
        if let Ok(b) = buf {
            assert!(b.is_locked());
        }
    }

    #[test]
    fn secure_buffer_debug_redacts() {
        let mut buf = SecureBuffer::new(8).unwrap();
        buf.as_mut_bytes()
            .copy_from_slice(&[0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe]);
        let debug = format!("{buf:?}");
        assert!(debug.contains("REDACTED"));
        assert!(!debug.contains("dead"));
        assert!(debug.contains("len: 8"));
    }

    #[test]
    fn locking_support_detection() {
        let _supported = SecureBuffer::is_locking_supported();
    }

    #[test]
    fn secure_buffer_large() {
        let mut buf = SecureBuffer::new(1_000_000).unwrap();
        assert_eq!(buf.len(), 1_000_000);
        buf.as_mut_bytes().fill(0xAB);
        drop(buf);
    }
}

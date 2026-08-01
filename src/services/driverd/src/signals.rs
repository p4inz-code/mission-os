//! D-Bus signal helper types for mission-driverd.
//!
//! Provides sequence numbering and timestamp helpers used by the
//! D-Bus signal emission functions in [`crate::dbus`].
//!
//! ## Architecture
//!
//! Per MOS-ENG-IPC-001 §4.4, signals include:
//!
//! 1. A sequence number for ordering (monotonically increasing).
//! 2. A Unix timestamp (seconds since epoch, UTC).

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Global signal sequence counter for ordering.
static SIGNAL_SEQUENCE: AtomicU64 = AtomicU64::new(0);

/// Return the next signal sequence number (monotonically increasing).
pub fn next_sequence() -> u64 {
    SIGNAL_SEQUENCE.fetch_add(1, Ordering::SeqCst)
}

/// Return the current Unix timestamp in seconds since epoch.
pub fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sequence_number_increases() {
        let a = next_sequence();
        let b = next_sequence();
        assert!(b > a);
    }

    #[test]
    fn sequence_number_is_monotonic() {
        let mut prev = next_sequence();
        for _ in 0..10 {
            let curr = next_sequence();
            assert!(curr > prev);
            prev = curr;
        }
    }

    #[test]
    fn timestamp_is_reasonable() {
        let ts = current_timestamp();
        // Must be after year 2001 and before year 2286
        assert!(ts > 1_000_000_000);
        assert!(ts < 9_999_999_999);
    }

    #[test]
    fn timestamp_is_reproducible() {
        let a = current_timestamp();
        let b = current_timestamp();
        // Timestamps can be equal if called within the same second
        assert!(b >= a);
    }
}

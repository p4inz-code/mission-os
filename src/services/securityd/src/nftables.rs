//! nftables-compatible rule generation.
//!
//! This module generates nftables-compatible rule strings from the
//! validated FirewallRule model defined in the firewall module.
//!
//! ## Architecture
//!
//! Per MOS-ENG-SEC-001 §6.1, the firewall backend is nftables.
//! This module generates the nftables configuration that can be
//! applied via `libnftables` or written to an nftables config file.
//!
//! ## Security
//!
//! - Generated rules are validated first (no raw nftables expressions).
//! - The default policy is deny-incoming, allow-outgoing.
//! - Rules are generated as structured nftables syntax — NOT as shell commands.
//! - No arbitrary strings are interpolated into rules without escaping.
//!
//! ## Current Status
//!
//! This module generates nftables ruleset strings. The actual execution
//! via `libnftables` or `nft` CLI is deferred — the rules are ready to
//! be applied when the execution engine is integrated.

use crate::config::FirewallProfile;
use crate::firewall::{Direction, FirewallRule, Protocol, RuleAction};

/// Error type for nftables rule generation.
#[derive(Debug, Clone)]
pub enum NftablesError {
    /// The rule is invalid and cannot be converted.
    InvalidRule(String),
    /// The profile is not supported for generation.
    UnsupportedProfile(String),
}

impl std::fmt::Display for NftablesError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NftablesError::InvalidRule(msg) => write!(f, "invalid rule: {msg}"),
            NftablesError::UnsupportedProfile(msg) => write!(f, "unsupported profile: {msg}"),
        }
    }
}

impl std::error::Error for NftablesError {}

/// Generate a complete nftables ruleset for the given profile and rules.
///
/// Returns the nftables configuration as a string, ready to be applied.
///
/// # Arguments
///
/// * `profile` — The firewall profile to generate rules for.
/// * `rules` — Additional custom rules to include.
pub fn generate_ruleset(profile: &FirewallProfile, rules: &[FirewallRule]) -> String {
    let mut lines = Vec::new();

    // Header
    lines.push("#!/usr/sbin/nft -f".to_string());
    lines.push(String::new());

    // Table definition
    lines.push("table inet mission_securityd {".to_string());

    // Generate chains based on profile
    match profile {
        FirewallProfile::Public => generate_public_chains(&mut lines),
        FirewallProfile::Private => generate_private_chains(&mut lines),
        FirewallProfile::Development => generate_development_chains(&mut lines),
        FirewallProfile::Custom => generate_custom_chains(&mut lines),
    }

    // Add user-defined rules
    for rule in rules {
        if let Ok(rule_str) = generate_rule(rule) {
            lines.push(format!("    {rule_str}"));
        }
    }

    lines.push("}".to_string());
    lines.push(String::new());
    lines.join("\n")
}

/// Generate the base chains for a "Public" profile (deny incoming, allow outgoing).
fn generate_public_chains(lines: &mut Vec<String>) {
    // Input chain — deny by default
    lines.push("    chain input {".to_string());
    lines.push("        type filter hook input priority 0; policy drop;".to_string());
    // Allow established/related connections
    lines.push("        ct state established,related accept".to_string());
    // Allow loopback
    lines.push("        iifname lo accept".to_string());
    // Allow ICMP (ping)
    lines.push("        ip protocol icmp accept".to_string());
    lines.push("    }".to_string());

    // Forward chain — deny by default
    lines.push(String::new());
    lines.push("    chain forward {".to_string());
    lines.push("        type filter hook forward priority 0; policy drop;".to_string());
    lines.push("    }".to_string());

    // Output chain — allow by default
    lines.push(String::new());
    lines.push("    chain output {".to_string());
    lines.push("        type filter hook output priority 0; policy accept;".to_string());
    lines.push("    }".to_string());
}

/// Generate chains for a "Private" profile (allow LAN, deny WAN incoming).
fn generate_private_chains(lines: &mut Vec<String>) {
    lines.push("    chain input {".to_string());
    lines.push("        type filter hook input priority 0; policy drop;".to_string());
    lines.push("        ct state established,related accept".to_string());
    lines.push("        iifname lo accept".to_string());
    // Allow LAN (RFC 1918)
    lines.push("        ip saddr 10.0.0.0/8 accept".to_string());
    lines.push("        ip saddr 172.16.0.0/12 accept".to_string());
    lines.push("        ip saddr 192.168.0.0/16 accept".to_string());
    lines.push("        ip protocol icmp accept".to_string());
    lines.push("    }".to_string());

    lines.push(String::new());
    lines.push("    chain forward {".to_string());
    lines.push("        type filter hook forward priority 0; policy drop;".to_string());
    lines.push("    }".to_string());

    lines.push(String::new());
    lines.push("    chain output {".to_string());
    lines.push("        type filter hook output priority 0; policy accept;".to_string());
    lines.push("    }".to_string());
}

/// Generate chains for a "Development" profile (allow selected ports).
fn generate_development_chains(lines: &mut Vec<String>) {
    lines.push("    chain input {".to_string());
    lines.push("        type filter hook input priority 0; policy drop;".to_string());
    lines.push("        ct state established,related accept".to_string());
    lines.push("        iifname lo accept".to_string());
    // Common development ports
    lines.push("        tcp dport 22 accept".to_string()); // SSH
    lines.push("        tcp dport 80 accept".to_string()); // HTTP
    lines.push("        tcp dport 443 accept".to_string()); // HTTPS
    lines.push("        tcp dport 3000 accept".to_string()); // Dev server
    lines.push("        tcp dport 8080 accept".to_string()); // Dev server
    lines.push("        ip protocol icmp accept".to_string());
    lines.push("    }".to_string());

    lines.push(String::new());
    lines.push("    chain forward {".to_string());
    lines.push("        type filter hook forward priority 0; policy drop;".to_string());
    lines.push("    }".to_string());

    lines.push(String::new());
    lines.push("    chain output {".to_string());
    lines.push("        type filter hook output priority 0; policy accept;".to_string());
    lines.push("    }".to_string());
}

/// Generate chains for a "Custom" profile (base structure only).
fn generate_custom_chains(lines: &mut Vec<String>) {
    lines.push("    chain input {".to_string());
    lines.push("        type filter hook input priority 0; policy drop;".to_string());
    lines.push("        ct state established,related accept".to_string());
    lines.push("        iifname lo accept".to_string());
    lines.push("        ip protocol icmp accept".to_string());
    lines.push("    }".to_string());

    lines.push(String::new());
    lines.push("    chain forward {".to_string());
    lines.push("        type filter hook forward priority 0; policy drop;".to_string());
    lines.push("    }".to_string());

    lines.push(String::new());
    lines.push("    chain output {".to_string());
    lines.push("        type filter hook output priority 0; policy accept;".to_string());
    lines.push("    }".to_string());
}

/// Generate an nftables rule string from a FirewallRule.
///
/// The generated rule is formatted for inclusion in the `input` chain
/// of the `inet mission_securityd` table.
pub fn generate_rule(rule: &FirewallRule) -> Result<String, NftablesError> {
    if !rule.enabled {
        return Ok(format!("# rule '{}' is disabled", rule.name));
    }

    // Validate first
    rule.validate().map_err(|e| {
        NftablesError::InvalidRule(format!("rule '{}' failed validation: {e}", rule.name))
    })?;

    let mut parts: Vec<String> = Vec::new();

    // Direction filter
    if rule.direction == Direction::In {
        // Rules in the input chain are incoming by default
    }

    // Source address
    if let Some(ref src) = rule.source {
        parts.push(format!("ip saddr {}", escape_addr(src)));
    }

    // Destination address
    if let Some(ref dst) = rule.destination {
        parts.push(format!("ip daddr {}", escape_addr(dst)));
    }

    // Protocol + ports
    match rule.protocol {
        Some(Protocol::Tcp) => {
            parts.push("tcp".to_string());
            if let Some(port) = rule.source_port {
                parts.push(format!("sport {port}"));
            }
            if let Some(port) = rule.destination_port {
                parts.push(format!("dport {port}"));
            }
        }
        Some(Protocol::Udp) => {
            parts.push("udp".to_string());
            if let Some(port) = rule.source_port {
                parts.push(format!("sport {port}"));
            }
            if let Some(port) = rule.destination_port {
                parts.push(format!("dport {port}"));
            }
        }
        Some(Protocol::Icmp) => {
            parts.push("ip protocol icmp".to_string());
        }
        Some(Protocol::Other) | None => {
            // No protocol filter
        }
    }

    // Action
    let action = match rule.action {
        RuleAction::Accept => "accept",
        RuleAction::Drop => "drop",
        RuleAction::Reject => "reject with icmpx admin-prohibited",
    };

    let rule_str = if parts.is_empty() {
        format!("        {}", action)
    } else {
        format!("        {} {}", parts.join(" "), action)
    };

    // Add comment with rule name
    Ok(format!("{rule_str} comment \"{}\"", rule.name))
}

/// Escape an address string for nftables.
/// Basic validation to prevent injection.
fn escape_addr(addr: &str) -> String {
    // Only allow CIDR notation characters
    let sanitized: String = addr
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '.' || *c == '/' || *c == ':')
        .collect();
    sanitized
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::firewall::Direction;
    use crate::firewall::RuleAction;

    fn sample_rule() -> FirewallRule {
        FirewallRule {
            name: "allow-ssh".into(),
            direction: Direction::In,
            action: RuleAction::Accept,
            protocol: Some(Protocol::Tcp),
            source: None,
            destination: None,
            source_port: None,
            destination_port: Some(22),
            enabled: true,
        }
    }

    #[test]
    fn generate_rule_ssh() {
        let rule = sample_rule();
        let result = generate_rule(&rule).unwrap();
        assert!(result.contains("tcp"));
        assert!(result.contains("dport 22"));
        assert!(result.contains("accept"));
        assert!(result.contains("allow-ssh"));
    }

    #[test]
    fn generate_rule_disabled() {
        let rule = FirewallRule {
            enabled: false,
            ..sample_rule()
        };
        let result = generate_rule(&rule).unwrap();
        assert!(result.starts_with('#'));
        assert!(result.contains("disabled"));
    }

    #[test]
    fn generate_rule_drop() {
        let rule = FirewallRule {
            action: RuleAction::Drop,
            ..sample_rule()
        };
        let result = generate_rule(&rule).unwrap();
        assert!(result.contains("drop"));
    }

    #[test]
    fn generate_rule_with_source() {
        let rule = FirewallRule {
            source: Some("10.0.0.0/8".into()),
            ..sample_rule()
        };
        let result = generate_rule(&rule).unwrap();
        assert!(result.contains("10.0.0.0/8"));
    }

    #[test]
    fn generate_ruleset_public() {
        let ruleset = generate_ruleset(&FirewallProfile::Public, &[]);
        assert!(ruleset.contains("table inet mission_securityd"));
        assert!(ruleset.contains("policy drop"));
        assert!(ruleset.contains("ct state established,related accept"));
    }

    #[test]
    fn generate_ruleset_private() {
        let ruleset = generate_ruleset(&FirewallProfile::Private, &[]);
        assert!(ruleset.contains("192.168.0.0/16"));
        assert!(ruleset.contains("10.0.0.0/8"));
    }

    #[test]
    fn generate_ruleset_development() {
        let ruleset = generate_ruleset(&FirewallProfile::Development, &[]);
        assert!(ruleset.contains("dport 22"));
        assert!(ruleset.contains("dport 80"));
        assert!(ruleset.contains("dport 443"));
        assert!(ruleset.contains("dport 3000"));
        assert!(ruleset.contains("dport 8080"));
    }

    #[test]
    fn generate_ruleset_custom() {
        let ruleset = generate_ruleset(&FirewallProfile::Custom, &[]);
        assert!(ruleset.contains("table inet mission_securityd"));
    }

    #[test]
    fn generate_ruleset_with_custom_rules() {
        let rule = sample_rule();
        let ruleset = generate_ruleset(&FirewallProfile::Public, &[rule]);
        assert!(ruleset.contains("allow-ssh"));
        assert!(ruleset.contains("dport 22"));
    }

    #[test]
    fn escape_addr_sanitizes() {
        let result = escape_addr("192.168.1.1/24");
        assert_eq!(result, "192.168.1.1/24");
    }

    #[test]
    fn invalid_rule_returns_error() {
        let rule = FirewallRule {
            name: "".into(),
            ..sample_rule()
        };
        let result = generate_rule(&rule);
        assert!(result.is_err());
    }
}

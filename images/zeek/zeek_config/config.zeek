# =============================================================================
# config.zeek - Zeek Configuration (PFA)
# =============================================================================
# Log all traffic on DMZ segment for protocol analysis
# =============================================================================
redef LogAscii::use_json = T;
redef Log::default_rotation_interval = 1hr;

# Local network
redef Site::local_nets = {
    10.0.1.0/24,
    10.0.2.0/24,
    10.0.3.0/24,
};

# Enable all default protocol analyzers
@load policy/protocols/ssh
@load policy/protocols/http
@load policy/protocols/ftp
@load policy/protocols/mysql
@load policy/protocols/conn
@load policy/protocols/dns
@load policy/protocols/ssl
@load policy/frameworks/files/hash-all-files
@load policy/frameworks/notice/weird
@load tuning/json-logs

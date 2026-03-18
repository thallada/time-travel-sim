"""
mitmproxy addon for the Time Travel Simulation.

Routing logic:
  - Requests to api.anthropic.com → pass through to real internet
  - All other requests → rewrite to HTTP and forward to WaybackProxy

The key challenge: WaybackProxy is an HTTP-only proxy. When a client
requests https://www.bbc.com, mitmproxy terminates TLS, but we need
to send WaybackProxy an HTTP request for http://www.bbc.com.
We reconstruct the URL as http:// and send it as an explicit proxy
request to WaybackProxy on port 8888.
"""

import re
from mitmproxy import http, ctx

# Domains that bypass WaybackProxy and go to the real internet
PASSTHROUGH_DOMAINS = {
    "api.anthropic.com",
    "mitm.it",  # mitmproxy's own cert distribution page
}

# Patterns to scrub from response bodies
SCRUB_PATTERNS = [
    (re.compile(r'<!--\s*BEGIN WAYBACK TOOLBAR.*?END WAYBACK TOOLBAR\s*-->', re.DOTALL | re.IGNORECASE), ''),
    # Primary: strip archive.org URL prefixes — [^/]+/ matches any timestamp+modifier
    (re.compile(r'https?://web\.archive\.org/web/[^/]+/', re.IGNORECASE), ''),
    # Fallback: catch any remaining archive.org URLs
    (re.compile(r'https?://web\.archive\.org[^\s"\'<>)]*', re.IGNORECASE), ''),
    # Wayback-injected scripts
    (re.compile(r'<script[^>]*(?:archive\.org|wayback)[^>]*>.*?</script>', re.DOTALL | re.IGNORECASE), ''),
    # Wayback-injected CSS
    (re.compile(r'<link[^>]*(?:archive\.org|wayback)[^>]*/?>', re.IGNORECASE), ''),
    # Wombat rewriting engine
    (re.compile(r'(?:var\s+)?_?wbhack[^;]*;', re.IGNORECASE), ''),
    (re.compile(r'WB_wombat_Init\([^)]*\);?', re.IGNORECASE), ''),
    # Archive meta tags
    (re.compile(r'<meta[^>]*archive\.org[^>]*/?>', re.IGNORECASE), ''),
    # Data attributes
    (re.compile(r'\s*data-(?:wayback|archive)[^=]*="[^"]*"', re.IGNORECASE), ''),
    # Any remaining text references
    (re.compile(r'archive\.org', re.IGNORECASE), ''),
]

SCRUB_HEADERS = [
    "x-archive-orig-",
    "x-archive-",
    "x-wayback-",
]


class TimeTravelRouter:
    def request(self, flow: http.HTTPFlow) -> None:
        original_host = flow.request.pretty_host

        if original_host in PASSTHROUGH_DOMAINS:
            ctx.log.info(f"[PASSTHROUGH] {flow.request.method} {flow.request.pretty_url}")
            return

        # Build the original HTTP URL (downgrade HTTPS → HTTP)
        # This is what WaybackProxy needs to look up in the archive
        original_path = flow.request.path  # includes query string
        http_url = f"http://{original_host}{original_path}"

        ctx.log.info(f"[WAYBACK] {flow.request.pretty_url} → {http_url}")

        # Rewrite the request to go to WaybackProxy as an explicit HTTP proxy request
        # In explicit proxy mode, the request line contains the full URL
        flow.request.scheme = "http"
        flow.request.host = "172.30.0.3"
        flow.request.port = 8888

        # Critical: set the URL that appears in the HTTP request line
        # WaybackProxy reads this to know what archived page to fetch
        flow.request.url = http_url

        # Ensure the Host header matches the original site
        flow.request.headers["Host"] = original_host

    def response(self, flow: http.HTTPFlow) -> None:
        # Don't scrub passthrough responses
        original_host = flow.request.headers.get("Host", flow.request.pretty_host)
        if original_host in PASSTHROUGH_DOMAINS:
            return

        # Scrub headers that might reveal archive.org
        headers_to_remove = []
        for header_name in flow.response.headers:
            for prefix in SCRUB_HEADERS:
                if header_name.lower().startswith(prefix):
                    headers_to_remove.append(header_name)
                    break

        for h in headers_to_remove:
            del flow.response.headers[h]

        # Replace server header if it mentions archive infrastructure
        server_header = flow.response.headers.get("server", "")
        if "archive" in server_header.lower() or "wayback" in server_header.lower():
            flow.response.headers["server"] = "Apache/2.2.15"

        # Scrub response body for text content
        content_type = flow.response.headers.get("content-type", "")
        if any(t in content_type for t in ["text/html", "text/css", "javascript", "application/json"]):
            try:
                body = flow.response.get_text()
                if body:
                    for pattern, replacement in SCRUB_PATTERNS:
                        body = pattern.sub(replacement, body)
                    flow.response.set_text(body)
            except Exception as e:
                ctx.log.warn(f"[SCRUB] Failed to scrub response: {e}")


addons = [TimeTravelRouter()]

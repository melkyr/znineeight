# M5 Task 2-I — real TLS 1.3 endpoint investigation

Date: 2026-10-22 (UTC)
Scope: read-only network investigation. No repo/source edits. Test artifacts were kept under `/tmp/task2i`; this report is the only workspace file written.

## Environment and method

```text
$ date -u
Thu Oct 22 23:51:51 UTC 2026

$ curl -V
curl 7.88.1 (x86_64-pc-linux-gnu) libcurl/7.88.1 OpenSSL/3.0.22 ...

$ openssl version
OpenSSL 3.0.22 25 Aug 2026 (Library: OpenSSL 3.0.22 25 Aug 2026)
```

`dig` was not installed in this environment despite the brief:

```text
$ command -v dig host nslookup
(no output)
```

DNS lookups used `getent ahostsv4`, e.g.:

```text
$ getent ahostsv4 www.microsoft.com | awk '{print $1}' | sort -u
23.2.70.86
```

A current Mozilla bundle was downloaded and used for all chain validation:

```text
$ curl -fsS -o /tmp/task2i/cacert.pem https://curl.se/ca/cacert.pem

$ curl -fsSI https://curl.se/ca/cacert.pem | grep -i last-modified
last-modified: Tue, 20 Oct 2026 13:32:40 GMT

$ grep -c 'BEGIN CERTIFICATE' /tmp/task2i/cacert.pem
118

$ sha256sum /tmp/task2i/cacert.pem
796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe
```

TLS checks were run with:

```sh
openssl s_client -4 -connect "$host:443" -servername "$host" \
  -showcerts -tls1_3 -CAfile /tmp/task2i/cacert.pem </dev/null
```

Certificates were split from the `-showcerts` output and inspected with:

```sh
openssl x509 -in cert.pem -noout -subject -issuer -serial -text
```

Chain + hostname validation used:

```sh
openssl verify -CAfile /tmp/task2i/cacert.pem \
  -untrusted intermediate.pem [-untrusted ...] \
  -verify_hostname "$host" leaf.pem
```

HTTP checks were made without redirect following, forcing TLS 1.3:

```sh
curl -4 -sS --max-time 30 --connect-timeout 10 \
  --tlsv1.3 --tls-max 1.3 -o body -D headers \
  -w 'code=%{http_code} ver=%{http_version} ip=%{remote_ip} redir=[%{redirect_url}] size=%{size_download}\n' \
  "$url"
```

Each title/hash/bot-marker check was repeated twice. The two TLS summary runs were byte-identical:

```text
$ diff /tmp/task2i/tlssum_run1.tsv /tmp/task2i/tlssum_run2.tsv
IDENTICAL
```

## Findings

### 1. RSA-certificate TLS 1.3 candidates

All rows below negotiated TLS 1.3 and used `Peer signature type: RSA-PSS` (unless noted). `chain_sigs` lists the signatures on the certificates actually sent after the leaf; `depth` is the number of certs sent by the server (the trust anchor is additional). Every tested chain validated against `/tmp/task2i/cacert.pem`, and the recommended endpoints also matched their hostname via `-verify_hostname`.

| Candidate | TLS 1.3 cipher | Leaf key | Leaf sig | Intermediate/root sigs (sent depth) | HTTP r1 / r2 | Body bytes | Verdict |
|---|---|---|---|---|---|---|---|
| `https://www.microsoft.com/` | AES-256-GCM | RSA-2048 | sha384WithRSAEncryption | sha384WithRSAEncryption > sha384WithRSAEncryption (3) | 200 block / 200 block; 2 additional timeouts, one HTTP/2 PROTOCOL_ERROR | 201253, same body hash | **Soft bot block**, not real page |
| `https://www.microsoft.com/en-us/` | AES-256-GCM | RSA-2048 | sha384WithRSAEncryption | sha384WithRSAEncryption > sha384WithRSAEncryption (3) | 200 block / 200 block (5/5 in separate loop) | 201253, same body hash | **Soft bot block**, not real page |
| `https://azure.microsoft.com/` | AES-256-GCM | RSA-2048 | sha384WithRSAEncryption | sha384WithRSAEncryption > sha384WithRSAEncryption (3) | 301 / 301 to `https://azure.microsoft.com/en-us` | 0 | Redirect; not usable without `-L` |
| `https://www.amazon.com/` | AES-128-GCM | RSA-2048 | sha256WithRSAEncryption | sha256WithRSAEncryption > sha256WithRSAEncryption (3) | 200 / 200 | 1072335 / 1072335 | Real page, no bot marker; dynamic body hash |
| `https://aws.amazon.com/` | AES-128-GCM | RSA-2048 | sha256WithRSAEncryption | sha256WithRSAEncryption > sha256WithRSAEncryption (3) | 200 / 200 | 509641 / 509641 | Real page, no bot marker; dynamic body hash |
| `https://www.deepseek.com/` | AES-128-GCM | RSA-2048 | sha256WithRSAEncryption | sha256WithRSAEncryption > sha256WithRSAEncryption (3) | 200 / 200 | 115760 / 115760, same hash | Real page, no bot marker |
| `https://www.apple.com/` | AES-256-GCM | RSA-2048 | sha256WithRSAEncryption | sha256WithRSAEncryption (2) | 200 / 200 | 326990 / 326990, same hash | Real page, no bot marker |
| `https://www.mozilla.org/` | AES-128-GCM | RSA-2048 | sha256WithRSAEncryption | sha256WithRSAEncryption > sha256WithRSAEncryption (3) | 200 / 200 | 47808 / 47808, same hash | Real page, no bot marker |
| `https://www.openssl.org/` | AES-256-GCM | RSA-2048 | sha256WithRSAEncryption | sha256WithRSAEncryption > sha256WithRSAEncryption (3) | 200 / 200 | 7057 / 7057, same hash | Real page, no bot marker |
| `https://www.sectigo.com/` | AES-256-GCM | RSA-2048 | sha256WithRSAEncryption | sha384WithRSAEncryption > sha384WithRSAEncryption > sha384WithRSAEncryption (4) | 200 / 200 | 700270 / 700270 | Real page, but body contains a `captcha` marker |
| `https://www.identrust.com/` | AES-256-GCM | RSA-4096 | sha256WithRSAEncryption | sha256WithRSAEncryption (2) | 200 / 200 | 139604 / 139604 | Real page, no bot marker; dynamic hash |

`adevjournal.info` was listed in the brief with the RSA candidates, but it currently presents an **ECDSA P-256** leaf and negotiates ECDSA, so it is covered in the ECDSA section instead.

Representative raw TLS output:

```text
$ openssl s_client -4 -connect aws.amazon.com:443 -servername aws.amazon.com \
    -showcerts -tls1_3 -CAfile /tmp/task2i/cacert.pem </dev/null | \
    grep -E '^New,|Peer signature type|Verify return code'
New, TLSv1.3, Cipher is TLS_AES_128_GCM_SHA256
Peer signature type: RSA-PSS
Verify return code: 0 (ok)

$ openssl verify -CAfile /tmp/task2i/cacert.pem \
    -untrusted intermediate.pem -untrusted amazon-root.pem \
    -verify_hostname aws.amazon.com leaf.pem
leaf.pem: OK
```

### 2. ECDSA TLS 1.3 candidates

All rows below negotiated TLS 1.3, reported `Peer signature type: ECDSA`, and validated against the Mozilla bundle.

| Candidate | TLS 1.3 cipher | Leaf key/curve | Leaf sig | Intermediate/root sigs (sent depth) | HTTP r1 / r2 | Body bytes | Verdict |
|---|---|---|---|---|---|---|---|
| `https://letsencrypt.org/` | AES-128-GCM | ECDSA P-256 | ecdsa-with-SHA384 | ecdsa-with-SHA384 > ecdsa-with-SHA384 > sha256WithRSAEncryption (4) | 200 / 200 | 90353 / 90353, same hash | Real page, no bot marker |
| `https://example.com/` | AES-256-GCM | ECDSA P-256 | ecdsa-with-SHA256 | ecdsa-with-SHA384 > ecdsa-with-SHA384 > sha256WithRSAEncryption (4) | 200 / 200 | 577 / 577, same hash | Real page, no bot marker |
| `https://www.cloudflare.com/` | AES-256-GCM | ECDSA P-256 | ecdsa-with-SHA256 | ecdsa-with-SHA384 > sha256WithRSAEncryption (3) | 200 / 200 | 1333889 / 1333889, same hash | Real page, but body contains a `captcha` marker |
| `https://github.com/` | AES-128-GCM | ECDSA P-256 | ecdsa-with-SHA256 | ecdsa-with-SHA384 > ecdsa-with-SHA384 (3) | 200 / 200 | 580227 / 580227 | Real page, but body contains a `captcha` marker |
| `https://www.whatsapp.com/` | CHACHA20-POLY1305 | ECDSA P-256 | sha256WithRSAEncryption | sha256WithRSAEncryption (2) | 200 / 200 | 280261 / 280259 | Real page, but body contains a `captcha` marker |
| `https://www.google.com/` | AES-256-GCM | ECDSA P-256 | ecdsa-with-SHA256 | ecdsa-with-SHA384 > sha256WithRSAEncryption (3) | 200 / 200 | 86387 / 86400 | Real page, no bot marker |
| `https://adevjournal.info/` | AES-256-GCM | ECDSA P-256 | ecdsa-with-SHA256 | ecdsa-with-SHA384 > sha256WithRSAEncryption (3) | 200 / 200 | 37956 / 37956, same hash | Real page, no bot marker |
| `https://www.nginx.com/` | AES-256-GCM | ECDSA P-256 | ecdsa-with-SHA384 | ecdsa-with-SHA384 > ecdsa-with-SHA384 > sha256WithRSAEncryption (4) | 301 / 301 to `https://www.f5.com/products/nginx` | 0 | Redirect; not usable |
| `https://www.namecheap.com/` | AES-256-GCM | **ECDSA P-384** | ecdsa-with-SHA256 | ecdsa-with-SHA384 > ecdsa-with-SHA384 > sha384WithRSAEncryption (4) | 403 / 403 | 5418 | Cloudflare challenge (`cf-mitigated: challenge`, title `Just a moment...`); not usable |

Representative raw TLS output:

```text
$ openssl s_client -4 -connect letsencrypt.org:443 -servername letsencrypt.org \
    -showcerts -tls1_3 -CAfile /tmp/task2i/cacert.pem </dev/null | \
    grep -E '^New,|Peer signature type|Verify return code'
New, TLSv1.3, Cipher is TLS_AES_128_GCM_SHA256
Peer signature type: ECDSA
Verify return code: 0 (ok)

$ openssl verify -CAfile /tmp/task2i/cacert.pem \
    -untrusted intermediate.pem -untrusted root-ye.pem -untrusted root-x2.pem \
    -verify_hostname letsencrypt.org leaf.pem
leaf.pem: OK
```

A usable P-384 **leaf** was found only at `www.namecheap.com`, but its HTTP endpoint is challenged (403), so it cannot serve the fetch tier. No other tested stable endpoint had a P-384 leaf; all clean usable ECDSA endpoints were P-256.

### 3. `www.microsoft.com` bot block and `/en-us/`

The context note that root returns bot-403 while `/en-us/` returns the real page is **not reproducible from this vantage point today**. Both paths return the same soft block page with HTTP 200.

Commands:

```sh
curl -4 -sS --max-time 20 --tlsv1.3 --tls-max 1.3 \
  -o /tmp/task2i/ms_en_b1.html -D /tmp/task2i/h \
  -w 'code=%{http_code} size=%{size_download} ip=%{remote_ip} redir=[%{redirect_url}]\n' \
  https://www.microsoft.com/en-us/
```

Observed for `/en-us/` (two runs):

```text
run=1 code=200 ver=2 ip=23.2.70.86 redir=[] size=201253
run=2 code=200 ver=2 ip=23.2.70.86 redir=[] size=201253
title=[Your request has been blocked. This could be due to several reasons.]
sha256 prefix=5965b2c5472aaca1
server: AkamaiNetStorage
```

Observed for `/` (two runs):

```text
run=1 code=200 ver=2 ip=23.2.70.86 redir=[] size=0  -> curl: (92) HTTP/2 stream 1 was not closed cleanly
run=2 code=200 ver=2 ip=23.2.70.86 redir=[] size=201253
title=[Your request has been blocked. This could be due to several reasons.]
sha256 prefix=5965b2c5472aaca1
```

Root and `/en-us/` produced the **same 201253-byte body and hash**. A separate five-request loop on `/` got three 200 block-page responses and two 20-second timeouts; a five-request loop on `/en-us/` got five 200 block-page responses. With an empty User-Agent, the server returned a hard 403 with a different 4410-byte page:

```text
$ curl ... -H 'User-Agent:' https://www.microsoft.com/
code=403 ver=2 size=4410 redir=[]
title=Microsoft
text: "Thank you for your patience ... We are currently experiencing high demand..."
```

Sending a full browser-like header set to `/en-us/` still returned the same 200 soft block page (same 201253 bytes and hash). Therefore the block is not caused by the `/en-us/` path; it is path-independent (likely Akamai/edge or source-IP reputation). `/en-us/` is **not stable as a real-content endpoint**: its status/bytes checks pass while the body is a block page. That is worse than a hard 403 for the tier because `status=200, bytes>0` silently accepts it. It still exercises the TLS 1.3 RSA-PSS handshake, but it does not satisfy the brief's requirement for a direct GET that returns real content without bot blocking.

### 4. TLS 1.2 fallback

Forced TLS 1.2 checks still returned real pages and validated chains:

```text
$ curl -4 -sS --tlsv1.2 --tls-max 1.2 ... https://www.google.com/
run1: code=200 ver=2 size=86415
run2: code=200 ver=2 size=86625

$ curl -4 -sS --tlsv1.2 --tls-max 1.2 ... https://example.com/
run1: code=200 ver=2 size=577
run2: code=200 ver=2 size=577

$ openssl s_client -4 -connect www.google.com:443 -servername www.google.com -tls1_2 ...
New, TLSv1.2, Cipher is ECDHE-ECDSA-CHACHA20-POLY1305
Peer signature type: ECDSA
Verify return code: 0 (ok)

$ openssl s_client -4 -connect example.com:443 -servername example.com -tls1_2 ...
New, TLSv1.2, Cipher is ECDHE-ECDSA-CHACHA20-POLY1305
Peer signature type: ECDSA
Verify return code: 0 (ok)
```

Both existing fallback hosts remain HTTP 200 with non-empty bodies. Note that both also support TLS 1.3; the internet-smoke `net_case` in `tier_tls.sh` does not force TLS 1.2, so it currently exercises the negotiated (TLS 1.3) path unless the client is explicitly restricted.

### 5. Local `openssl s_server` test certificates

Current local TLS 1.3 setup:

```text
tests/certs/localhost.pem: RSA-2048, sha256WithRSAEncryption
tests/certs/root.pem: RSA, sha256WithRSAEncryption
tier_tls.sh run_local13(): s_server -tls1_3 -cert localhost.pem -key localhost.key
```

Both TLS 1.3 suite runs use the RSA leaf, so local coverage exercises RSA-PSS but not ECDSA CertificateVerify. Recommendation: **do not replace** the RSA leaf (it is the local RSA-PSS coverage). **Add** ECDSA leaves signed by the existing test root:

- `localhost-p256.pem` / key, `prime256v1` (ECDSA P-256 / SHA-256).
- `localhost-p384.pem` / key, `secp384r1` (ECDSA P-384 / SHA-384).
- Add TLS 1.3 `s_server` cases using those leaves; keep at least one AES-128-GCM and one ChaCha20-Poly1305 case for suite coverage, and keep the RSA-PSS case.
- No trust-store change is needed if the new leaves are signed by the existing `root.pem` (the local store pins that root).

This would give local coverage for ECDSA P-256, ECDSA P-384, and RSA-PSS. The remote P-384 case cannot be covered by a clean public endpoint found here.

## Recommendation

- **RSA-PSS TLS 1.3 smoke**
  - Primary: `https://aws.amazon.com/`
  - Fallback: `https://www.mozilla.org/`
  - Alternate if AWS is regionally blocked: `https://www.deepseek.com/`
  - Do **not** keep `www.microsoft.com/en-us/` as the primary RSA smoke; it returns a 200 soft-block page from this vantage point.
- **ECDSA TLS 1.3 smoke**
  - Primary: `https://letsencrypt.org/` (ECDSA P-256, no challenge, stable body)
  - Fallback: `https://example.com/` (ECDSA P-256, 577-byte stable body; also usable for the TLS 1.2 fallback)
  - `www.cloudflare.com`, `github.com`, and `www.whatsapp.com` work but carry in-page captcha markers; `www.nginx.com` redirects; `www.namecheap.com` is P-384 but Cloudflare-challenged.
- **TLS 1.2 fallback**
  - Primary: `https://www.google.com/`
  - Fallback: `https://example.com/`
  - If this is intended to test TLS 1.2 specifically, force `--tls-max 1.2` (or the equivalent client option) in the smoke; otherwise it negotiates TLS 1.3.

## Concerns / limitations

- `dig` was unavailable; DNS was checked with `getent`, so no resolver-level TTL/record evidence is included.
- Results are from a single datacenter egress at 2026-10-22. Bot blocking and CDN edge selection can vary by source IP and time; the Microsoft result is explicitly path-independent here but may differ elsewhere.
- `www.microsoft.com` can return a hard 403, a soft 200 block page, an HTTP/2 protocol error, or a timeout. Any tier assertion based only on `status=200` and `bytes>0` can pass on the soft block page.
- Large dynamic pages (Amazon, AWS, GitHub, WhatsApp, etc.) have unstable body hashes even when byte sizes are stable; only status/body length should be asserted, not content hashes.
- Public certificates and chains rotate; the recorded chain signature algorithms are point-in-time observations. Re-validate the Mozilla bundle before treating the store as current.

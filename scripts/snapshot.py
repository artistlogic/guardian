#!/usr/bin/env python3
"""Export Sentry alerts to data/alerts.json (fallback data source for the dashboard).

Run where outbound RPC works:
  RPC_URL=https://sepolia.gateway.tenderly.co python3 scripts/snapshot.py
Then commit data/alerts.json.
"""

import json
import os
import ssl
import sys
import urllib.request

CALLBACK = os.environ.get("CALLBACK_ADDR", "0xa070a801f8cd3f844e41e672d9e42380485cabe0")
RPC = os.environ.get("RPC_URL", "https://sepolia.gateway.tenderly.co")
SPAN = int(os.environ.get("BLOCK_SPAN", "120000"))
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "alerts.json")
CTX = ssl._create_unverified_context()


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        RPC, data=body,
        headers={"Content-Type": "application/json", "User-Agent": "sentry-snapshot/1.0"},
    )
    with urllib.request.urlopen(req, timeout=30, context=CTX) as resp:
        out = json.loads(resp.read())
    if "error" in out:
        raise RuntimeError(out["error"])
    return out["result"]


def word(data, i):
    raw = data[2:] if data.startswith("0x") else data
    return int(raw[i * 64 : (i + 1) * 64], 16)


def main():
    head = int(rpc("eth_blockNumber", []), 16)
    start = max(head - SPAN, 0)
    logs, CHUNK = [], 9000
    for end in range(head, start, -CHUNK):
        frm = max(end - CHUNK, start)
        part = rpc("eth_getLogs", [{"address": CALLBACK,
                                    "fromBlock": hex(frm), "toBlock": hex(end)}])
        logs.extend(part)

    items, blocks = [], {}
    origin_ts = {}
    for log in logs:
        bn = log["blockNumber"]
        if bn not in blocks:
            b = rpc("eth_getBlockByNumber", [bn, False])
            blocks[bn] = int(b["timestamp"], 16)
        origin_tx = "0x" + format(word(log["data"], 1), "064x")
        if origin_tx not in origin_ts:
            try:
                rc = rpc("eth_getTransactionReceipt", [origin_tx])
                obn = rc["blockNumber"] if rc else None
                if obn and obn not in blocks:
                    ob = rpc("eth_getBlockByNumber", [obn, False])
                    blocks[obn] = int(ob["timestamp"], 16)
                origin_ts[origin_tx] = blocks.get(obn) if obn else None
            except Exception:
                origin_ts[origin_tx] = None
        items.append({
            "callbackTx": log["transactionHash"],
            "originTx": origin_tx,
            "originTs": origin_ts.get(origin_tx),
            "value": str(word(log["data"], 2)),
            "ts": blocks[bn],
            "block": int(bn, 16),
        })

    items.sort(key=lambda x: x["block"], reverse=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"contract": CALLBACK, "generatedAt": head, "items": items}, f, indent=2)
    print(f"wrote {len(items)} alerts -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

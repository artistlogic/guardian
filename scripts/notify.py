#!/usr/bin/env python3
"""Guardian off-chain notifier (ntfy.sh).

Polls the destination-chain GuardianCallback contract for `Alert` logs and
pushes each one to an ntfy topic. No account or token needed.

Subscribe on your phone (ntfy app) or in a browser:
  https://ntfy.sh/<NTFY_TOPIC>

Usage (PowerShell):
  $env:NTFY_TOPIC="dy-guardian-2026"
  $env:CALLBACK_ADDR="0xa070a801f8cd3f844e41e672d9e42380485cabe0"
  python notify.py

Optional:
  $env:RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
  $env:POLL_SECONDS="15"
  $env:START_BLOCK="12170000"
"""

import json
import os
import ssl
import time
import urllib.request

NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "dy-guardian-2026")
NTFY_URL = os.environ.get("NTFY_URL", "https://ntfy.sh")
RPC_URL = os.environ.get("RPC_URL", "https://ethereum-sepolia-rpc.publicnode.com")
CALLBACK = os.environ["CALLBACK_ADDR"]
POLL = int(os.environ.get("POLL_SECONDS", "15"))
DECIMALS = 18

_INSECURE = ssl._create_unverified_context()


def _urlopen(req, timeout=20):
    """Always use an unverified context: this environment MITMs TLS (proxy/AV)."""
    return urllib.request.urlopen(req, timeout=timeout, context=_INSECURE)


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        RPC_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "guardian-notifier/1.0",
        },
    )
    with _urlopen(req) as resp:
        out = json.loads(resp.read())
    if "error" in out:
        raise RuntimeError(out["error"])
    return out["result"]


def notify(title, text, click=None):
    headers = {"Title": title.encode("ascii", "ignore").decode(), "Tags": "rotating_light"}
    if click:
        headers["Click"] = click
    req = urllib.request.Request(
        f"{NTFY_URL}/{NTFY_TOPIC}",
        data=text.encode(),
        headers={**headers, "User-Agent": "guardian-notifier/1.0"},
    )
    with _urlopen(req) as resp:
        return resp.status


def word(data_hex, i):
    raw = data_hex[2:] if data_hex.startswith("0x") else data_hex
    return int(raw[i * 64 : (i + 1) * 64], 16)


def main():
    if os.environ.get("START_BLOCK"):
        start = int(os.environ["START_BLOCK"])
    else:
        start = int(rpc("eth_blockNumber", []), 16)
    print(f"[guardian] watching {CALLBACK} -> ntfy topic '{NTFY_TOPIC}' from block {start}")
    last = start
    while True:
        try:
            head = int(rpc("eth_blockNumber", []), 16)
            if head >= last:
                logs = rpc(
                    "eth_getLogs",
                    [{"address": CALLBACK, "fromBlock": hex(last), "toBlock": hex(head)}],
                )
                for log in logs:
                    # Alert(address indexed reactive, uint256 chainId,
                    #       uint256 originTxHash, uint256 value, uint256 alertIndex)
                    origin_tx_hash = word(log["data"], 1)
                    value = word(log["data"], 2)
                    amount = value / 10**DECIMALS
                    origin_tx = "0x" + format(origin_tx_hash, "064x")
                    cb_tx = log["transactionHash"]
                    link = f"https://eth-sepolia.blockscout.com/tx/{cb_tx}"
                    notify(
                        "Sentry Alert",
                        f"金额 {amount:.4f} D3RT\n源交易 {origin_tx}\n回调交易 {cb_tx}",
                        click=link,
                    )
                    print(f"[guardian] alerted origin={origin_tx} callback={cb_tx} value={amount}")
                last = head + 1
        except Exception as e:
            print(f"[guardian] error: {e}")
        time.sleep(POLL)


if __name__ == "__main__":
    main()

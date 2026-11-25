#!/usr/bin/env python3
"""Guardian off-chain notifier.

Polls the destination-chain GuardianCallback contract for `Alert` logs and
pushes each one to a Telegram chat.

Usage:
  export TG_TOKEN=123456:ABC...        # from @BotFather
  export TG_CHAT_ID=123456789          # your chat/channel id
  export RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
  export CALLBACK_ADDR=0xa070a801f8cd3f844e41e672d9e42380485cabe0
  python3 scripts/notify.py

Optional:
  export POLL_SECONDS=15
  export START_BLOCK=12170000          # default: current block
"""

import json
import os
import time
import urllib.parse
import urllib.request

TG_TOKEN = os.environ["TG_TOKEN"]
TG_CHAT_ID = os.environ["TG_CHAT_ID"]
RPC_URL = os.environ.get("RPC_URL", "https://ethereum-sepolia-rpc.publicnode.com")
CALLBACK = os.environ["CALLBACK_ADDR"]
POLL = int(os.environ.get("POLL_SECONDS", "15"))
DECIMALS = 18


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        RPC_URL, data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        out = json.loads(resp.read())
    if "error" in out:
        raise RuntimeError(out["error"])
    return out["result"]


def send(text):
    data = urllib.parse.urlencode({"chat_id": TG_CHAT_ID, "text": text}).encode()
    url = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"
    with urllib.request.urlopen(url, data=data, timeout=20) as resp:
        return resp.read()


def word(data_hex, i):
    raw = data_hex[2:] if data_hex.startswith("0x") else data_hex
    return int(raw[i * 64 : (i + 1) * 64], 16)


def main():
    start = int(os.environ.get("START_BLOCK", rpc("eth_blockNumber", []), 16))
    print(f"[guardian] watching {CALLBACK} from block {start}, every {POLL}s")
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
                    # Alert(address indexed reactive, uint256 chainId, uint256 originTxHash, uint256 value, uint256 alertIndex)
                    origin_tx = word(log["data"], 1)
                    value = word(log["data"], 2)
                    amount = value / 10**DECIMALS
                    tx = log["transactionHash"]
                    msg = (
                        "🚨 Guardian Alert\n"
                        f"源交易: {tx}\n"
                        f"金额: {amount:.4f} D3RT\n"
                        f"回调: https://eth-sepolia.blockscout.com/tx/{tx}"
                    )
                    send(msg)
                    print(f"[guardian] alerted {tx} value={amount}")
                last = head + 1
        except Exception as e:  # keep polling on transient RPC errors
            print(f"[guardian] error: {e}")
        time.sleep(POLL)


if __name__ == "__main__":
    main()

## OGuard

** OGuard is a deterministic on-chain execution firewall that prevents privileged key compromise exploits by enforcing dynamic behavioral constraints at the transaction level before any damage can occur.
 



## The Problem


Pre-deployment tools can't catch operational infrastructure failures. Traditional monitoring tools can only alert you after the state transition has already occurred. OGuard enforces economic invariants inline, stopping the exploit mid-execution.

---

## What OGuard Does

Every mint request passes three sequential checks:

1. Is this key registered in OGuard's registry?
2. Is this key currently active and not frozen?
3. Does this mint stay within 5% of live pool liquidity per 24 hours?

All three must pass. Any failure reverts the transaction atomically.
Zero tokens minted. Zero damage.

---

## Repository Structure
src/
HAIToken.sol              # Simulates the vulnerable token pattern
OGuard.sol                # The execution firewall
test/
Mocks.sol                 # Simulates DEX pool liquidity
OGuard.t.sol              # Five proof-of-concept tests
ARCHITECTURE.md             # Full technical design document
README.md                   # This file

---

## Running the PoC

```bash
forge install
forge test -vv
```

Expected output:
[PASS] test_NormalMintSucceeds()
[PASS] test_HackenExploitBlocked()
[PASS] test_UnregisteredKeyBlocked()
[PASS] test_FrozenKeyBlocked()
[PASS] test_TrickleMintHitsCeiling()
5 passed — 0 failed

---

## Notes ( Known Limitations for this demo )

**Flash loan manipulation**  
OGuard reads spot pool liquidity. Production fix: TWAP oracle.  
This is a known, solved engineering problem, spot price is just used 
here for the purpose of demonstrating the core mechanism clearly.

**Residual risk within ceiling**  
A compromised key minting within the daily ceiling will pass Rule 3.  
- Every mint emits a visible on-chain event, monitoring catches 
anomalous recipients on day one. Emergency freeze closes the window.

**Manual freeze dependency**  
Production fix: automated off-chain monitor connected to cloud 
provider APIs that calls freezeKey() on server decommission events.

---

## Full Architecture

check [ARCHITECTURE.md](./ARCHITECTURE.md) for complete technical 
design including component breakdown, adoption model, and future work.

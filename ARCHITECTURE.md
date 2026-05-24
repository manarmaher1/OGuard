# OGuard: On-Chain Execution Firewall Architecture

## Overview
`OGuard` is an on-chain execution firewall designed as a runtime security layer for privileged token actions. Instead of relying purely on passive off-chain monitoring or simple static role-based access control (RBAC), `OGuard` acts as an inline gateway that evaluates transaction payloads against real-time protocol invariants before allowing state updates to finalize.

This architecture specifically mitigates risks associated with operational infrastructure failures—such as the June 2025 Hacken $HAI bridge key compromise—where an adversary gains control of a valid cryptographic administrative key but attempts an economically catastrophic action.

---

## System Components & Trust Boundaries

The system is split into three core smart contract environments, separating the target asset logic, the live market data dependency, and the runtime firewall enforcement logic.

```
[Privileged Key / Bridge Server]
│
▼ (requestMint)
┌───────────────┐
│    OGuard     │ ◄───Reads Reserves─── [Uniswap V2 / Mock Pool]
│   (Firewall)  │
└───────┬───────┘
│ (if checks pass, internal mint)
▼
┌───────────────┐
│   HAIToken    │
└───────────────┘
```
### 1. The Gateway Firewall (`OGuard.sol`)
* **Role:** The core execution gatekeeper. It inherits no external dependencies and maintains an isolated internal key registry.
* **Privilege State:** It must be granted exclusive administrative or minting rights over the target token contract (`token.transferOwnership(address(oGuard))`).

### 2. The Target Asset (`HAIToken.sol`)
* **Role:** The underlying ERC-20 token contract.
* **Privilege State:** Completely decoupled from external infrastructure servers. Its native `mint()` function is strictly gatekept by the `onlyOwner` modifier, pointing exclusively to the `OGuard` deployment address.

### 3. The Market Oracle Reference (`MockDexPool.sol` / Automated Market Maker)
* **Role:** Provides the external economic state used to scale safety thresholds dynamically.
* **Privilege State:** Untrusted read-only dependency. `OGuard` queries its spot reserves synchronously during the execution pipeline.

---

## Transaction Execution Pipeline

Every mint invocation follows a strict, non-bypassable sequence of execution inside `requestMint()`. If any step fails, the entire transaction triggers an atomic EVM `revert()`, preserving previous state balances and consuming adversarial gas.

### Step 1: Registry Authorization Check
The firewall queries its tightly packed `keys` storage mapping using `msg.sender`.
* If `status == KeyStatus.UNREGISTERED`, execution reverts with `KeyNotRegistered()`.

### Step 2: Operational Status Check
The key's activity lifecycle is evaluated.
* If `status == KeyStatus.FROZEN`, execution reverts with `KeyNotActive()`. This allows immediate protocol isolation by a multisig owner without modifying core token code.

### Step 3: Dynamic Economic Ceiling Evaluation
* **Epoch Resolution:** The system normalizes time into fixed Unix calendar days (`block.timestamp / 1 days`) to mitigate continuous rolling window tracking gas overhead.
* **Liquidity Query:** The firewall calls `getReserves()` on the paired automated market maker (AMM) pool, programmatically mapping the correct reserve slot matching the asset.
* **Ceiling Computation:** The dynamic volume ceiling is calculated based on configured Basis Points (BPS) against live pool depth:
  ``` 
  $$\text{Dynamic Ceiling} = \frac{\text{Current Pool Liquidity} \times \text{maxPoolImpactBps}}{\text{BPS\_DENOMINATOR}}$$
  *Real Hacken numbers:* $\frac{20,000,000 \times 500}{10,000} = 1,000,000 \text{ HAI per epoch day}$
  ```
  
* **Invariant Enforcement:** The cumulative volume already minted in the current epoch day plus the incoming transaction `amount` is checked against the computed ceiling.
  * If $\text{Global Minted Volume} + \text{Amount} > \text{Dynamic Ceiling}$, execution reverts with `DynamicLiquidityCeilingBreached()`.

### Step 4: Downstream Interaction
If all sequential validation checks pass, the daily epoch cumulative volume is updated with the new amount, and the firewall triggers the low-level execution call: `token.mint(to, amount)`.

---

## Operational Security Considerations & Vulnerability Surface

While `OGuard` introduces native defensive resilience against compromised keys, a production-grade deployment must account for the following vector trade-offs identified during architectural evaluation:

### 1. Spot Liquidity Manipulation (Flash Loan Risk)
* **Threat:** Because the baseline implementation calculates the dynamic ceiling using raw spot pool reserves (`IMockDexPool.getReserves()`), the firewall's safety boundaries are vulnerable to intra-block manipulation. An attacker can execute a flash loan to temporarily inflate pool depth, artificially scaling up the dynamic ceiling to push a massive mint payload through in a single transaction block.
* **Production Mitigation:** Replace direct spot AMM queries with a Time-Weighted Average Liquidity (TWAL) oracle or integrate a decentralized price feed (e.g., Chainlink) to smooth out flash variations. This is a known, solved engineering problem—spot price is used here to demonstrate the core mechanism clearly.

### 2. EVM Storage & Gas Optimization
* **Optimization:** Core authorization parameters are stored inside an individual packed struct (`KeyStatus`), keeping storage reads constrained to a cheap `SLOAD` execution pattern. Human-readable diagnostic data (`infrastructureTag`) is decoupled entirely from the validation pipeline and held in an isolated metadata mapping (`keyMetadata`) to ensure operational monitoring doesn't incur runtime gas penalties.


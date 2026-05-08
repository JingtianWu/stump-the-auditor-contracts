# Stump the AI Auditor Submission

## Contract

Lending (`src/Lending/Lending.sol`)

## GitHub Repo URL

https://github.com/JingtianWu/stump-the-auditor-contracts/tree/codex/stump-challenge

## Lite Scan URL

https://aiauditor.certik.com/en/scan/60417bd2-3db4-4d8c-ab7f-5752248a8d06

## Severity Claim

Critical: protocol insolvency / uncollateralized bad debt.

## Vulnerability

The reserve-parameter validation was changed so the protocol permits the exact boundary where:

```text
liquidationThresholdBps * (BPS + liquidationBonusBps) == BPS * BPS
```

This happens through two individually plausible changes: raising `MAX_LIQ_BONUS_BPS` from `2_000` to `2_500`, and changing the combined invariant from `>=` to `>`. Either change alone does not enable this boundary: the higher bonus would still be constrained by the combined invariant, and `>` is effectively inert under the old 20% max bonus. Together, they allow `liquidationThresholdBps = 8_000` and `liquidationBonusBps = 2_500`, where `80% * 125% == 100%`.

## Impact

At the boundary, a borrower can borrow up to 80% of collateral value while liquidation seizes exactly 125% collateral value per unit of repaid debt. This consumes the entire collateral buffer: repaying the initial 80% debt seizes 100% of collateral. After any debt interest accrues, a liquidator can repay the original principal-sized amount and receive all collateral, while the accrued debt remains with zero collateral and health factor 0. Suppliers cannot withdraw their full indexed claim because the pool lacks enough liquidity, leaving uncollateralized bad debt and permanently frozen yield.

## Exploit Steps

1. Admin lists or updates a collateral reserve with `collateralFactorBps = 8_000`, `liquidationThresholdBps = 8_000`, and `liquidationBonusBps = 2_500`.
2. A lender supplies 1,600 USDC.
3. The attacker supplies 1 WETH worth 2,000 USD.
4. The attacker borrows 1,600 USDC, exactly at the 80% collateral limit.
5. Time passes and interest accrues on the USDC debt.
6. A liquidator repays 1,600 USDC and receives all 1 WETH collateral at the 25% liquidation bonus.
7. The borrower has no collateral but still has accrued debt. The lender's indexed USDC claim exceeds pool liquidity and a full withdrawal reverts.

## Proof

Run:

```bash
forge test --match-contract PlantPoC -vv
```

PoC:

```text
test/PlantPoC.t.sol::testPoC_boundaryBonusLeavesUncollateralizedDebtAndFrozenSupplierClaim
```

Full suite:

```bash
forge test
```

Expected result: all tests pass, including the PoC.

## Why This Is A Realistic Mistake

The max liquidation bonus increase looks like a normal risk-parameter product change, and the `>=` to `>` edit looks like allowing equality at a mathematical boundary. The subtle issue is that equality is not safe in an interest-bearing debt system: once debt interest accrues, the zero-buffer liquidation configuration has no margin to absorb debt growth, so liquidation can exhaust collateral before debt is cleared.

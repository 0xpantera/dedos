# StarkNet Denial of Service Attacks Demo

This project demonstrates two common Denial of Service (DoS) vulnerabilities in StarkNet smart contracts. Each example shows how a malicious actor can exploit certain contract design patterns to render them unusable.

## Overview

The repository contains two main examples:

1. **Bank Contract DoS** - A vulnerability where directly sending tokens to a contract breaks its internal accounting
2. **Auction Contract DoS** - A vulnerability where flooding a contract with transactions makes it impossible to process them due to gas limits

Both examples demonstrate how seemingly innocuous design decisions can lead to contracts becoming completely unusable.

## Bank Contract Attack

### Vulnerability

The `StarknetBank` contract has an internal accounting check that ensures the contract's recorded total balance matches its actual token balance. While this seems like a prudent security measure, it creates a critical vulnerability.

```cairo
fn _check_accounting(self: @ContractState) {
    assert(
        self.currency.read().balance_of(get_contract_address()) == self.total_balance.read(),
        'Accounting issue'
    );
}
```

### Attack Vector

An attacker can simply transfer tokens directly to the contract address, bypassing the deposit function that would update the accounting. This causes a mismatch between the contract's actual balance and its recorded total, making the accounting check fail for all future transactions.

```cairo
// The attack
eth_dispatcher.transfer(bank_address, helpers::one_ether());
```

After this attack, any legitimate user trying to deposit or withdraw will face a transaction revert due to the "Accounting issue" error, effectively breaking the contract permanently.

## Auction Contract Attack

### Vulnerability

The `Auction` contract allows users to bid on items and includes a mechanism to refund losing bids when an auction completes. The refund process happens in a loop that processes each bid:

```cairo
let mut i = 0;
while i < item_bids.len() - 1 {
    let mut current_bid = item_bids[i];
    self.eth.read().transfer(current_bid.bidder, current_bid.amount);
    // Reset bid...
    i += 1;
};
```

### Attack Vector

An attacker can exploit this design by creating a large number of small bids for an auction. When the auction owner tries to accept the highest bid, the function has to process every single bid in the refund loop. If there are too many bids, the transaction will exceed the gas limit and revert:

```cairo
// Create a lot of bids for the same item
let mut i: u256 = 2;
while i < 1000 {
    start_cheat_caller_address(eth_address, attacker);
    eth_dispatcher.approve(auction_address, i);
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(auction_address, attacker);
    auction_dispatcher.bid(1, i);
    stop_cheat_caller_address(auction_address);
    i += 1;
}
```

This attack prevents the auction from ever completing, locking both the NFT and all the bids (including legitimate ones) in the contract indefinitely.

## Mitigation Strategies

### For the Bank Contract

1. Don't tie critical functionality to external state that can be manipulated
2. Use a pull payment pattern where users withdraw funds themselves
3. Consider tracking external and internal deposits separately

### For the Auction Contract

1. Implement a "pull" refund mechanism instead of pushing refunds in a loop
2. Set a reasonable limit on the number of bids per auction
3. Process refunds in batches to avoid gas limits

## Running the Tests

To run the test cases demonstrating these attacks:

```bash
scarb test
```

## Project Structure

- `dedos/src/banco/` - Bank contract and its DoS attack test
- `dedos/src/auction/` - Auction contract and its DoS attack test
- `dedos/src/utils/` - Helper functions and mock contracts for testing

## Conclusion

These examples highlight the importance of defensive programming in smart contract development. Carefully consider how your contracts handle external interactions and avoid designs that could be vulnerable to DoS attacks.

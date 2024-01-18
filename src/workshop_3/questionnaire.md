## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?

```
Answer: EVC gives every Ethereum account 256 addresses. Sub account addresses are created by XORing the owning address with the sub-account ID.
```

1. Does the sub-account system decrease the security of user accounts?

```
Answer: No, the su-account system does not decrease the security of the user accounts.
The EVC handles Authentication. Vaults don't need to know anything about sub-accounts.
```

1. Provide a couple of use cases for the operator functionality of the EVC.

```
Answer: Here are a couple of use-cases for the operator fucntionality:
1. It can allow a hot-wallet to perform trades but not withdrawals.
2. It can allow external users to perfrom specific actions on your account based on market conditions.
```

1. What is the main difference between the operator and the controller?

```
Answer: Controllers are similar to operators, but they can call users associated collateral vaults for liquidations.
```

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?

```
Answer: If a vault is called directly, requiring a vault status check will verify the check is immidiately satisfied. If a vault is called from an EVC batch, all checks are put into a queue and verified later.
The purpose of this deferral is for the checks to be performed at the end of batch.
```

1. Why is it useful to allow re-entrancy for `call` and `batch` functions?

```
Answer: It helps in crafting a much better user experience by batching multiple and complex interaction into one seamless step.
```

1. How does the simulation feature of the EVC work?

```
Answer: User add operations to the builder and only when the conditions are satisfied is an actual transaction executed.
```

1. Provide a couple of use cases for the `permit` functionality of the EVC.

```
Answer: The permit method allows users to sign the batch and have another entitty execute it on their behalf.
Use case 1: It can provide a more general permitting system than allowance in ERC-20 tokens
Use case 2: It can delegate authority to smart contract wallets like with ERC-1271
```

1. What is the purpose of the nonce namespace?

```
Answer: It's a way to segment streams of execution orders. From the presentation with Doug the nonce namesapces are tracked by the EVC itself.
```

1. Why should the EVC neither be given any privileges nor hold any tokens?

```
Answer: The EVC should not be given any privileges or hold any tokens due to the risks associated with its ability to execute arbitrary calldata, the control exerted by the Controller Vault, and the diverse nature of assets that can be used as collateral within the protocol.

```

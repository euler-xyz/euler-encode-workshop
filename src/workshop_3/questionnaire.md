## Workshop 3 Assignment:

`

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
On the EVC (Ethereum Vault Connector), every Ethereum address is associated with 256 sub-accounts. The addresses of these sub-accounts are calculated by XORing the owning address with a unique sub-account ID. The sub-account IDs range from 1 to 255.
   For example, if the owning address is: 315e56e361882129ae4f68038af45bf6ac6b3c2b then address of sub-account 1 would be calculated as: (315e56e361882129ae4f68038af45bf6ac6b3c2b ^ 1)= 315e56e361882129ae4f68038af45bf6ac6b3c2a

1. Does the sub-account system decrease the security of user accounts?
 No, it isn't the XORing mechanism ensures that each sub-account has a distinct and deterministic address.The EVC handles authentication, and vaults do not need to understand the details of sub-accounts

1. Provide a couple of use cases for the operator functionality of the EVC.
 Users can enable or disable these operators based on their preferences or market conditions. This allows for the implementation of sophisticated trading strategies without requiring constant observation.Allowing a “hot wallet” to perform trades but not withdrawals

1. What is the main difference between the operator and the controller?
 Multiple subaccounts can be linked with operators also operators can perform actions on behalf of the account.But in case of the controller user can't control and he cant disable the controller until users is in able clear his debts/borrowed token.

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
 By deferring checks until the end of the batch, gas costs are reduced because the system consolidates and verifies multiple status checks in a single operation.Moreover, the deferral allows for a unique flexibility. In cases where a check might be temporarily violated during the batch,Vault status checks are for verifying global vault properties.

1. Why is it useful to allow re-entrancy for call and batch functions?
Allowing re-entrancy in call and batch functions provides users with a powerful and flexible mechanism for composing multiple operations in a single transaction, while also ensuring atomicity, gas efficiency, and proper authentication.

1. How does the simulation feature of the EVC work?
In a normal batch call, return data is not typically returned to the caller to save gas costs. However, the simulation feature provides a mechanism to simulate the execution of a batch, collect return data, and handle errors in a way that allows for more detailed analysis.Also the caller can then analyze the caught error data to understand the outcomes of each operation within the batch

1. Provide a couple of use cases for the permit functionality of the EVC.
Permit allows to gasless transactions its a method to sign batches of transactions and delegating to third person/party,the permit method can be invoked by keepers.In evc permit calls the msg.sender as EVC itself so it actually works for authenticted users.

1. What is the purpose of the nonce namespace?
By nonce namespaces all transactions will be occured in a order,so that it cant be happened multiple times.Each users has mapping from nonce namespace to nonce.Initially the nonceNamespace will be 0 after sign sequentially it increases nonces.

1. Why should the EVC neither be given any privileges nor hold any tokens?
 Keeping it without special privileges aligns with the principles of decentralization, ensuring that no single entity or contract has undue control over the system.Can build many protocols with interacting external smart contracts under this EVC systems,By not holding tokens, it avoids conflicts of interest that may arise if it were to have a stake in the assets or outcomes of the transactions, ensuring fair

`

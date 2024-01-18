## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
   * An Ethereum address has up to 256 virtual sub-accounts (including the main account) that are completely in isolation from one another
   * The addresses are calculated from the main account using "XOR" operation on the main account. These sub-accounts share the same first 19 bytes of the main account.
1. Does the sub-account system decrease the security of user accounts?
   * No, it does not.
1. Provide a couple of use cases for the operator functionality of the EVC.
   * The operator when approved by a user, can act on behalf of the user's account. It can be useful in the following use cases:
     
     1. It manages the user's account by modifying/changing the account's collateral or controller sets, enabling vaults as collateral.
     2. An operator can manage a "keeper" by allowing it to close out the user's position(take-profit, stoploss) when specific conditions are met 
1. What is the main difference between the operator and the controller?
   * In the case of an operator, an account owner can grant or revoke access at any time, while the Controller exclusively retains the authorization to revoke its privileges on the account.
   * An account operator can change the collateral or controller sets while the Controller has no permission to do.
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
   * Deferring account/vault status checks delay the verification/check of the status of the account and vault until a later time or under specific conditions.
     ## Purpose:
   * In the case of batching, multiple call operations can be performed within a single batch operation by deferring the liquidity checks until the end of the batch.
     
     Overall, it prevents transient violations from causing a failure.
   
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
   * Facilitating re-entrancy for call and batch functions in Ethereum Vault Connector (EVC) enhances the support for batch functions, enabling atomic operations, deferred liquidity checks, and conditional checks. This results in more efficient and flexible transaction processing.
1. How does the simulation feature of the EVC work?
   *The Ethereum Vault Connector (EVC) simulation feature, triggered by batchSimulation(), distinguishes itself from standard batch() calls by collecting return data from each batch item and reverting with it as error data. This resilient mechanism, utilizing try-catch exceptions, remains effective even on nodes that may tamper with error data.
1. Provide a couple of use cases for the `permit` functionality of the EVC.
   * Facilitated by the Permit functionality, enable the creation of "resting" orders. In this context, permit messages remain in a mempool until specific conditions, such as time, price, or on-chain metrics, are met, triggering their execution.
   * The Permit functionality within Ethereum Vault Connector (EVC) empowers users to sign permit messages containing transaction details, removing the necessity for users to directly initiate blockchain transactions.
1. What is the purpose of the nonce namespace?
   * The nonce namespace provides increased flexibility in the arrangement and reuse of permit messages. When setting namespace=0 and incrementing nonce sequentially, it resembles a standard Ethereum transaction, requiring single-use adherence in a specific order.
   However, users have the option to deterministically set the namespace based on the message contents, like namespace=keccak256(message). This approach allows permits with different namespaces to be reordered at will or remain unused.
1. Why should the EVC neither be given any privileges nor hold any tokens?
   * The EVC is intentionally crafted as a generic system without inherent authority. The sole exception to this principle is a momentary holding of value or tokens within a single batch call

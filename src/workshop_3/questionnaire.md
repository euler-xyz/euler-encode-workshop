## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
Answer: We can have 256 sub-accounts on a ethereum address, this addresses are calculated by doing XOR operation of subaccontID, it's just xor, the first 19 bytes remains same only the last byte we try to generate different subaccounts through xor from 0 to 255(total 256 sub-accounts) with the subaccount0(your ethereum address)

1. Does the sub-account system decrease the security of user accounts?
Answer:No, they never jump to anywhere, it's bound to EVC, fully isolated to each other.However users giving their subaccounts to malicious operators leads to security issues.

1. Provide a couple of use cases for the operator functionality of the EVC.
Answer:Its really helps in trading when the users dont want to check everytime, so users can make custom operators that allows keepers to  perform when specific conditions mets like Stop-losses so that closing out the positions it can't be liqudated from users collteral, also operators are useful if any bugs happened in code,security violated it's better to withdraw your funds.


1. What is the main difference between the operator and the controller?
Answer: The difference between operator and the controller is we can remove our operators at any point of time, but in case of controller the vault manages,does only when we have no borrowed amount,if not also it can seize your collatoral inorder to repay the dept,so only the controller itself can call disableController on the EVC.

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
Answer: In vault status checks we do we take snapshot initial state basically use to verify the global vault properties, use this snapshots checks whenever EVC performs vault checks, coming to deferral vaults will requests to EVC then it checks, in another case while doing a multi batchrequest, all checks will be added into queue, verified at the end of the batch,the main purpose is to maintain efficient gas, so it checks at the end which saves a lot of gas fees.Also we can setup leverage positions with deferred checks.


1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
Answer: EVC allows us to do multi call operations,executing the  multiple operations in batch , making gas efficient so that multiple operations can't be broken.


1. How does the simulation feature of the EVC work?
Answer: Doing Simulations in a batch as part of EVC so calling the  'batchSimulation' every single item in the batch , every call is returned,so we can view all the returned data at the end, if any error occurs will go into try-catch exceptions and returning those error data.

1. Provide a couple of use cases for the `permit` functionality of the EVC.
Answer:This allows us to sign a batch and give permission to someone who can execute on their behalf.Using the permit functionality, the system can ensure that only authorized users can execute to particular functions.Also it enables Gasless Transactions making good UI in defi.

1. What is the purpose of the nonce namespace?
Answer: The top level account(subaccount(0)) which has unlimited no of nonce namespaces, so we have other subaccounts in which we can sequenece in anyorder of their transactions, can execute them in any order,also we can merge them.Point to remember is only aftere those transactions are executed then the next order allowed to execute.

1. Why should the EVC neither be given any privileges nor hold any tokens?
Answer: The main functionality of EVC is to provide basica functionality which required for a lending-borrwing market,on the top of this we can build customised vaults. Also we use 'permit' function making it to set BehalfOfAccount, only authorized users to access specific resources.
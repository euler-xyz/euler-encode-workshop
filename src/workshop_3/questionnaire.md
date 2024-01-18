## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
	- upto 256 sub-account. And they are calculated by XOR opteration on the address.
1. Does the sub-account system decrease the security of user accounts?
	- No, because all sub-accounts are isolated from eachother.
1. Provide a couple of use cases for the operator functionality of the EVC.
	- Stop loss, Take profit, Trailing stop loss, self directed liquidation...
1. What is the main difference between the operator and the controller?
	- Operator can be removed by user, while controller is only removed by EVC.
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
	- Deferring account and vault status checks mean putting all checks into queue and verifing later incase of EVC batch. Incase of direct vault call, vault status check will verify the check is satisfied immediately.
	- purpose for defer is to save on gas fee and allow failed operation in mid-batch (before end of batch).
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
	- Re-entrancy via `call` ensures that vaults always operate within a "checks deferred" context, even when called directly. this simplifies vault logic and improves security.
	- Re-entrancy within `batch` allows status checks to be deferred until the end of the batch, this means low gas and improved efficiency and atomic operations.
1. How does the simulation feature of the EVC work?
	- EVC Simulation is done in `batchSimulation()`, where every batch item is executed and the collected return data of all items is reverted with the data in a try-catch exception returning the caught error data.
1. Provide a couple of use cases for the `permit` functionality of the EVC.
	- Gasless execution or non-native assets as gas payment, Resting orders like one-cancels-other
1. What is the purpose of the nonce namespace?
	- Main purpose is to offer flexibility in transaction sequencing, by relaxing the sequencing restrictions.
1. Why should the EVC neither be given any privileges nor hold any tokens?
	- EVC is a vault mediation system, thus giving EVC privileges to access or hold tokens creates:
		- Security issue by central point of failure, 
		- Centralization of power into hands of EVC developers and 
		- loss of efficiency in tracking tokens held.

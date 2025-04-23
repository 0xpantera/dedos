#[starknet::interface]
pub trait IStarknetBank<TContractState> {
    fn deposit(ref self: TContractState, amount: u256);
    fn withdraw(ref self: TContractState, amount: u256);
    fn get_balance(self: @TContractState) -> u256;
    fn get_total_balance(self: @TContractState) -> u256;
}

#[starknet::contract]
mod StarknetBank {
    use starknet::{get_contract_address, get_caller_address, ContractAddress};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>, // Balance of each user in the Bank, address -> balance
        currency: IERC20Dispatcher, // The currency contract
        total_balance: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState, currency: ContractAddress) {
        self.currency.write(IERC20Dispatcher { contract_address: currency });
    }

    #[abi(embed_v0)]
    impl IStarknetBankImpl of super::IStarknetBank<ContractState> {
        // Deposit currency into the bank and increases the balance of the caller
        // @param amount: The amount to deposit
        fn deposit(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let balance = self.balances.read(caller);
            self.balances.write(caller, balance + amount);
            self.total_balance.write(self.total_balance.read() + amount);
            self.currency.read().transfer_from(caller, get_contract_address(), amount);
            self._check_accounting();
        }

        // Withdraw currency from the bank and decreases the balance of the caller
        // @param amount: The amount to withdraw
        fn withdraw(ref self: ContractState, amount: u256) {
            let mut amount = amount;
            let caller = get_caller_address();
            let balance = self.balances.read(caller);
            assert(balance >= amount, 'Not enough balance');
            self.balances.write(caller, balance - amount);
            self.total_balance.write(self.total_balance.read() - amount);
            self.currency.read().transfer(caller, amount);
            self._check_accounting();
        }

        // Get the balance of the caller
        fn get_balance(self: @ContractState) -> u256 {
            let caller = get_caller_address();
            self.balances.read(caller)
        }

        // Get the total balance of the bank
        fn get_total_balance(self: @ContractState) -> u256 {
            self.total_balance.read()
        }
    }

    #[generate_trait]
    impl InternalFunction of InternalFunctionTrait {
        // Check the accounting of the bank, makes sure the total balance is correct
        fn _check_accounting(self: @ContractState) {
            assert(
                self.currency.read().balance_of(get_contract_address()) == self.total_balance.read(), 
                'Accounting issue'
            );
        }
    }
}

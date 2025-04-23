use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, ClassHash};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, 
    start_cheat_caller_address, stop_cheat_caller_address, 
    start_cheat_block_timestamp
};
use dedos::banco::bank::{IStarknetBankDispatcher, IStarknetBankDispatcherTrait};

use dedos::utils::helpers;

fn deploy_bank(currency: ContractAddress) -> (ContractAddress, IStarknetBankDispatcher) {
    // Declaring the contract class
    let contract_class = declare("StarknetBank").unwrap().contract_class();
    // Creating the data to send to the constructor, first specifying as a default value
    let mut data_to_constructor = Default::default();
    // Pack the data into the constructor
    Serde::serialize(@currency, ref data_to_constructor);

    // Deploying the contract, and getting the address
    let (address, _) = contract_class.deploy(@data_to_constructor).unwrap();
    return (address, IStarknetBankDispatcher { contract_address: address });
}

#[test]
#[should_panic]
fn test_dos_1() {
    // Creating users
    let alice: ContractAddress = 'alice'.try_into().unwrap();
    let bob: ContractAddress = 'bob'.try_into().unwrap();
    let attacker: ContractAddress = 'attacker'.try_into().unwrap();

    // Deploying the contracts
    let (eth_address, eth_dispatcher) = helpers::deploy_eth();
    let (bank_address, bank_dispatcher) = deploy_bank(eth_address);

    // Mint 10 ETH for Alice, 20 for Bob and 1 for the attacker
    helpers::mint_erc20(eth_address, alice, 10 * helpers::one_ether());
    helpers::mint_erc20(eth_address, bob, 20 * helpers::one_ether());
    helpers::mint_erc20(eth_address, attacker, helpers::one_ether());

    // Alice deposit 10 tokens
    start_cheat_caller_address(eth_address, alice);
    eth_dispatcher.approve(bank_address, 10 * helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(bank_address, alice);
    bank_dispatcher.deposit(10 * helpers::one_ether());
    stop_cheat_caller_address(bank_address);

    // Bob deposit 20 tokens
    start_cheat_caller_address(eth_address, bob);
    eth_dispatcher.approve(bank_address, 20 * helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(bank_address, bob);
    bank_dispatcher.deposit(20 * helpers::one_ether());
    stop_cheat_caller_address(bank_address);

    // Alice withdraw 5 tokens
    start_cheat_caller_address(bank_address, alice);
    bank_dispatcher.withdraw(5 * helpers::one_ether());
    stop_cheat_caller_address(bank_address);

    // ATTACK START //
    // TODO: Attack the Bank contract so now one will be able to use it!
    
    // ATTACK END //

    // Alice tries to deposit 1 ETH to the bank, this should fail after the attack succeded.
    start_cheat_caller_address(eth_address, alice);
    eth_dispatcher.approve(bank_address, helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(bank_address, alice);
    bank_dispatcher.deposit(helpers::one_ether());
    stop_cheat_caller_address(bank_address);
}

